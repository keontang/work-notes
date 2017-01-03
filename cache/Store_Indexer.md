# Related files

1. pkg/client/cache/store.go
2. pkg/client/cache/index.go
3. pkg/client/cache/thread_safe_store.go

# Store interface

*pkg/client/cache/store.go*

```
// Store is a generic object storage interface. Reflector knows how to watch a server
// and update a store. A generic store is provided, which allows Reflector to be used
// as a local caching system, and an LRU store, which allows Reflector to work like a
// queue of items yet to be processed.
//
// Store makes no assumptions about stored object identity; it is the responsibility
// of a Store implementation to provide a mechanism to correctly key objects and to
// define the contract for obtaining objects by some arbitrary key type.
type Store interface {
    Add(obj interface{}) error
    Update(obj interface{}) error
    Delete(obj interface{}) error
    List() []interface{}
    ListKeys() []string
    /* key object --> key string --> stored object */
    Get(obj interface{}) (item interface{}, exists bool, err error)
    /* key string --> stored object */
    GetByKey(key string) (item interface{}, exists bool, err error)

    // Replace will delete the contents of the store, using instead the
    // given list. Store takes ownership of the list, you should not reference
    // it after calling this function.
    Replace([]interface{}, string) error
}
```

Store 是一个通用的`对象存储接口`，不对存储对象的身份做任何假设，也就是说可以存储任何对象；除了提供存储的一些常用方法（Add/Update/Delete/List 等）外，Store 接口的`实现代码`还需要提供一个机制，通过这个机制来校正`关键字对象`（即通过该`关键字对象`生成 `string 类型的关键字`, 体现在 `Store.Get()` 方法上），并且定义一种能够通过任何关键字类型获取对应的`存储对象`的方法（key object --> key string --> stored object）。

另外，我们还需要了解 `KeyFunc` 这个类型。

```
// KeyFunc knows how to make a key from an object. Implementations should be deterministic.
type KeyFunc func(obj interface{}) (string, error)
```

KeyFunc 为`函数类型`，实现该类型的函数必须明确的指定如何从 `key object` 生成 `key string`。

# Indexer interface

在分析 Indexer 之前，先大概回顾一下索引的概念。

## 数据库索引

索引是对数据库表中一列或多列的值进行排序的一种结构。 

在关系数据库中，索引是一种与表有关的数据库结构，它可以使对应于表的SQL语句执行得更快。

举个例子，我们用 map[string]sets.String 结构来建立索引：

name | age | heigth
---- | --- | ------
sam | 21 | 175
jim | 20 | 180
tank | 21 | 172
mike | 22 | 175

我们可以根据`索引值 age` 来建立索引记录：map["age"] = {"20", "21", "22"}

也可以根据`索引值 height` 来建立索引记录：map["height"] = {"172", "175", "180"}

## Indexer interface

*pkg/client/cache/index.go*

```
// IndexFunc knows how to provide an indexed value for an object.
type IndexFunc func(obj interface{}) ([]string, error)
```

IndexFunc 类型根据对象来生成索引值列表（一个对象是可以拥有多个索引值的）。我们知道，一个对象可以拥有多个 `lable`，我们可以给每个 `lable` 创建一个索引：`lable name` --> `a set of object name`，此时我们就可以创建这样一个 `IndexFunc` 函数：该函数返回对象的所有 `lable name`。

```
// Indexer is a storage interface that lets you list objects using multiple indexing functions
type Indexer interface {
    Store
    // Retrieve list of objects that match on the named indexing function
    Index(indexName string, obj interface{}) ([]interface{}, error)
    // ListIndexFuncValues returns the list of generated values of an Index func
    ListIndexFuncValues(indexName string) []string
    // ByIndex lists object that match on the named indexing function with the exact key
    ByIndex(indexName, indexKey string) ([]interface{}, error)
}

// Index maps the indexed value to a set of keys in the store that match on that value
/*
 * 采用 map[string]sets.String 数据结构来保存索引记录
 * 索引记录：索引值（the indexed value）--> key 集合
 */
type Index map[string]sets.String

// Indexers maps a name to a IndexFunc
/*
 * indexName --> IndexFunc 的映射
 *
 * 创建 Indexer 的时候，我们只需要指定该数据结构就可以了，参考 NewIndexer 函数
 * 当 Store.Add 的时候，Indexer 机制会自动更新 Index，
 * 即更新 Indices map：indexName --> Index，
 * 和 Index map：the indexed value --> a set of object name
 */
type Indexers map[string]IndexFunc

// Indices maps a name to an Index
/*
 * indexName --> Index 的映射
 */
type Indices map[string]Index
```

Indexer 也是一个存储接口，除了包含了 Store 接口的方法外，同时还允许我们使用多个索引方法来列出对象。也就是说，Indexer 除了跟 Store 一样能存储 key --> object 映射之外，还对 key 值建立了索引。

### Index(indexName string, obj interface{}) ([]interface{}, error)

从 indexName 的索引中列出与 obj 的索引值（a list of indexed value from obj）对应的对象列表（a list of object）。具体逻辑如下：

1. 通过 indexName 从 Indexers 中找到 IndexFunc
2. 通过 IndexFunc 找出 obj 的 索引值（a list of indexed value）
3. 通过 indexName 从 Indices 中找到 Index
4. 从 Index 中找到索引值对应的数据列表（a list of object name or a list of key name）
5. 根据 key name 从 items map 中获取 object 列表

### ListIndexFuncValues(indexName string) []string

列出 indexName 索引的所有索引值，即 indexName 对应的 Index map 的所有 key。那为什么函数名这么奇怪呢？下面我们来分析一下。

我们知道 Index map 保存的是索引记录，每条索引记录为：索引值（the indexed value）--> 数据集合。而索引值（the indexed value）是通过各个 obj 的 IndexFunc 输出的，所以列出所有 obj 的 IndexFunc 的输出值实际上就是列出 indexName 索引的所有索引值。现在看来，这个函数名一点都不怪了吧。

### ByIndex(indexName, indexKey string) ([]interface{}, error)

列出 indexName 索引中 indexKey 索引值对应的对象列表（a list of object）。其中，indexKey 属于所有 obj 的 IndexFunc 输出中的一个值。具体逻辑如下：

1. 检查是否能通过 indexName 从 Indexers 中找到 IndexFunc
2. 通过 indexName 从 Indices 中找到 Index
3. 从 Index 中找到 indexKey 对应的数据列表（a list of object name or a list of key name）
4. 根据 key name 从 items map 中获取 object 列表

# ThreadSafeStorage interface

*pkg/client/cache/thread_safe_store.go*

```
// ThreadSafeStore is an interface that allows concurrent access to a storage backend.
// TL;DR caveats: you must not modify anything returned by Get or List as it will break
// the indexing feature in addition to not being thread safe.
//
// The guarantees of thread safety provided by List/Get are only valid if the caller
// treats returned items as read-only. For example, a pointer inserted in the store
// through `Add` will be returned as is by `Get`. Multiple clients might invoke `Get`
// on the same key and modify the pointer in a non-thread-safe way. Also note that
// modifying objects stored by the indexers (if any) will *not* automatically lead
// to a re-index. So it's not a good idea to directly modify the objects returned by
// Get/List, in general.
type ThreadSafeStore interface {
    Add(key string, obj interface{})
    Update(key string, obj interface{})
    Delete(key string)
    Get(key string) (item interface{}, exists bool)
    List() []interface{}
    ListKeys() []string
    Replace(map[string]interface{}, string)
    Index(indexName string, obj interface{}) ([]interface{}, error)
    ListIndexFuncValues(name string) []string
    ByIndex(indexName, indexKey string) ([]interface{}, error)
}
```

从接口名字也可以看出 ThreadSafeStore interface 是线程安全的，允许多线程并发访问存储后端。

**注意：**

1. 实现了 `ThreadSafeStore` 并不意外着实现了 `Store`， 因为 `ThreadSafeStore interface` 中缺少 `Store interface` 的 `GetByKey` 方法。
2. 我们绝对不能修改 Get 或者 List 方法返回的任何值，因为这就破坏了索引功能而导致非线程安全。由 List/Get 提供的线程安全性的保证仅在调用者将返回的值视为只读时有效。举个例子，通过 Add 方法添加到 store 的指针可以通过 Get 方法返回，可能出现多个线程通过相同的关键字来 Get 到这个指针，并以非线程安全的方式修改指针。同样，修改由索引器（如果存在的话）存储的对象不会自动导致重新索引。因此，一般来说，直接修改 Get/List 返回的对象不是一个好主意。

# cache struct

*pkg/client/cache/store.go*

```
// cache responsibilities are limited to:
//  1. Computing keys for objects via keyFunc
//  2. Invoking methods of a ThreadSafeStorage interface
type cache struct {
    // cacheStorage bears the burden of thread safety for the cache
    cacheStorage ThreadSafeStore
    // keyFunc is used to make the key for objects stored in and retrieved from items, and
    // should be deterministic.
    keyFunc KeyFunc
}
```

cache 结构的责任有两个:

1. 通过 cache.keyFunc 来计算`存储对象的关键字`
2. 调用 `ThreadSafeStorage` 接口的方法

我们看看 cache struct 实现了哪些方法。

```
// Add inserts an item into the cache.
func (c *cache) Add(obj interface{}) error {
    key, err := c.keyFunc(obj)
    if err != nil {
        return KeyError{obj, err}
    }
    c.cacheStorage.Add(key, obj)
    return nil
}

// Update sets an item in the cache to its updated state.
func (c *cache) Update(obj interface{}) error {
    key, err := c.keyFunc(obj)
    if err != nil {
        return KeyError{obj, err}
    }
    c.cacheStorage.Update(key, obj)
    return nil
}

// Delete removes an item from the cache.
func (c *cache) Delete(obj interface{}) error {
    key, err := c.keyFunc(obj)
    if err != nil {
        return KeyError{obj, err}
    }
    c.cacheStorage.Delete(key)
    return nil
}

// List returns a list of all the items.
// List is completely threadsafe as long as you treat all items as immutable.
func (c *cache) List() []interface{} {
    return c.cacheStorage.List()
}

// ListKeys returns a list of all the keys of the objects currently
// in the cache.
func (c *cache) ListKeys() []string {
    return c.cacheStorage.ListKeys()
}

// Index returns a list of items that match on the index function
// Index is thread-safe so long as you treat all items as immutable
func (c *cache) Index(indexName string, obj interface{}) ([]interface{}, error) {
    return c.cacheStorage.Index(indexName, obj)
}

// ListIndexFuncValues returns the list of generated values of an Index func
func (c *cache) ListIndexFuncValues(indexName string) []string {
    return c.cacheStorage.ListIndexFuncValues(indexName)
}

func (c *cache) ByIndex(indexName, indexKey string) ([]interface{}, error) {
    return c.cacheStorage.ByIndex(indexName, indexKey)
}

// Get returns the requested item, or sets exists=false.
// Get is completely threadsafe as long as you treat all items as immutable.
func (c *cache) Get(obj interface{}) (item interface{}, exists bool, err error) {
    key, err := c.keyFunc(obj)
    if err != nil {
        return nil, false, KeyError{obj, err}
    }
    return c.GetByKey(key)
}

// GetByKey returns the request item, or exists=false.
// GetByKey is completely threadsafe as long as you treat all items as immutable.
func (c *cache) GetByKey(key string) (item interface{}, exists bool, err error) {
    item, exists = c.cacheStorage.Get(key)
    return item, exists, nil
}

// Replace will delete the contents of 'c', using instead the given list.
// 'c' takes ownership of the list, you should not reference the list again
// after calling this function.
func (c *cache) Replace(list []interface{}, resourceVersion string) error {
    items := map[string]interface{}{}
    for _, item := range list {
        key, err := c.keyFunc(item)
        if err != nil {
            return KeyError{item, err}
        }
        items[key] = item
    }
    c.cacheStorage.Replace(items, resourceVersion)
    return nil
}

// NewStore returns a Store implemented simply with a map and a lock.
func NewStore(keyFunc KeyFunc) Store {
    return &cache{
        cacheStorage: NewThreadSafeStore(Indexers{}, Indices{}),
        keyFunc:      keyFunc,
    }
}

// NewIndexer returns an Indexer implemented simply with a map and a lock.
func NewIndexer(keyFunc KeyFunc, indexers Indexers) Indexer {
    return &cache{
        cacheStorage: NewThreadSafeStore(indexers, Indices{}),
        keyFunc:      keyFunc,
    }
}
```

我们可以看出，cache struct 不仅实现了 Store 接口，而且也实现了 Indexer 接口，而且方法内部基本上调用了 cache.cacheStorage 的对应方法（除了 Get 方法），所以 cache 又利用了 cacheStorage 来保证线程安全。

我们可以用 `NewStore` 函数返回一个`简单的用 map 和 lock 实现的 Store`，也可以用 `NewIndexer` 函数返回一个`简单的用 map 和 lock 实现的 Indexer`。

`NewThreadSafeStore` 函数如下：

```
// pkg/client/cache/thread_safe_store.go

func NewThreadSafeStore(indexers Indexers, indices Indices) ThreadSafeStore {
    return &threadSafeMap{
        items:    map[string]interface{}{},
        indexers: indexers,
        indices:  indices,
    }
}
```

下面我们看看实现了 `ThreadSafeStore` 接口的 `threadSafeMap` 结构。

## threadSafeMap struct

```
// threadSafeMap implements ThreadSafeStore
type threadSafeMap struct {
    lock  sync.RWMutex
    items map[string]interface{}

    // indexers maps a name to an IndexFunc
    indexers Indexers
    // indices maps a name to an Index
    indices Indices
}
```

`threadSafeMap struct` 结构实现了一个线程安全的 `map`（通过 sync.RWMutex 来保证）。如果 `indexers` 为空（那么 `indices` 也为空）的话，那么 threadSafeMap 就实现了一个 `Store`；如果指定了 `indexers`，那么 threadSafeMap 就实现了一个 `Indexer`。

下面我们看看 `threadSafeMap` 对 `ThreadSafeStore` 接口的实现代码：

```
// pkg/client/cache/thread_safe_store.go

func (c *threadSafeMap) Add(key string, obj interface{}) {
    c.lock.Lock()
    defer c.lock.Unlock()
    oldObject := c.items[key]
    c.items[key] = obj
    c.updateIndices(oldObject, obj, key)
}

func (c *threadSafeMap) Update(key string, obj interface{}) {
    c.lock.Lock()
    defer c.lock.Unlock()
    oldObject := c.items[key]
    c.items[key] = obj
    c.updateIndices(oldObject, obj, key)
}

func (c *threadSafeMap) Delete(key string) {
    c.lock.Lock()
    defer c.lock.Unlock()
    if obj, exists := c.items[key]; exists {
        c.deleteFromIndices(obj, key)
        delete(c.items, key)
    }
}

func (c *threadSafeMap) Get(key string) (item interface{}, exists bool) {
    c.lock.RLock()
    defer c.lock.RUnlock()
    item, exists = c.items[key]
    return item, exists
}

func (c *threadSafeMap) List() []interface{} {
    c.lock.RLock()
    defer c.lock.RUnlock()
    list := make([]interface{}, 0, len(c.items))
    for _, item := range c.items {
        list = append(list, item)
    }
    return list
}

// ListKeys returns a list of all the keys of the objects currently
// in the threadSafeMap.
func (c *threadSafeMap) ListKeys() []string {
    c.lock.RLock()
    defer c.lock.RUnlock()
    list := make([]string, 0, len(c.items))
    for key := range c.items {
        list = append(list, key)
    }
    return list
}

func (c *threadSafeMap) Replace(items map[string]interface{}, resourceVersion string) {
    c.lock.Lock()
    defer c.lock.Unlock()
    c.items = items

    // rebuild any index
    c.indices = Indices{}
    for key, item := range c.items {
        c.updateIndices(nil, item, key)
    }
}

// Index returns a list of items that match on the index function
// Index is thread-safe so long as you treat all items as immutable
func (c *threadSafeMap) Index(indexName string, obj interface{}) ([]interface{}, error) {
    c.lock.RLock()
    defer c.lock.RUnlock()

    /* 1. 通过 indexName 获取该 index 的 IndexFunc 函数 */
    indexFunc := c.indexers[indexName]
    if indexFunc == nil {
        return nil, fmt.Errorf("Index with name %s does not exist", indexName)
    }

    /* 2. 通过 IndexFunc 函数获取 obj 的 indexed values, 这些 indexed values 是 Index map 的 key */
    indexKeys, err := indexFunc(obj)
    if err != nil {
        return nil, err
    }

    /* 3. 通过 indexName 获取该 index 的 Index map */
    index := c.indices[indexName]

    // need to de-dupe the return list.  Since multiple keys are allowed, this can happen.
    returnKeySet := sets.String{}

    /* 4. 从该 index 的 Index map 中获取 indexed values 对应的 key 值  */
    for _, indexKey := range indexKeys {
        set := index[indexKey]
        for _, key := range set.List() {
            returnKeySet.Insert(key)
        }
    }

    list := make([]interface{}, 0, returnKeySet.Len())

    /* 5. 根据获得的 key 值，取出对应的 object */
    for absoluteKey := range returnKeySet {
        list = append(list, c.items[absoluteKey])
    }
    return list, nil
}

// ByIndex returns a list of items that match an exact value on the index function
func (c *threadSafeMap) ByIndex(indexName, indexKey string) ([]interface{}, error) {
    c.lock.RLock()
    defer c.lock.RUnlock()

    /*
     * 1. 检查是否能通过 indexName 从 Indexers 中找到 IndexFunc
     *
     * 如果 IndexFunc 不存在的话，那么 indexed values 也是非法的
     */
    indexFunc := c.indexers[indexName]
    if indexFunc == nil {
        return nil, fmt.Errorf("Index with name %s does not exist", indexName)
    }

    /* 2. 通过 indexName 获取该 index 的 Index map */
    index := c.indices[indexName]

    /* 3. 从该 index 的 Index map 中获取 indexKey 索引对应的 key 值  */
    set := index[indexKey]
    list := make([]interface{}, 0, set.Len())

    /* 4. 根据获得的 key 值，取出对应的 object */
    for _, key := range set.List() {
        list = append(list, c.items[key])
    }

    return list, nil
}

func (c *threadSafeMap) ListIndexFuncValues(indexName string) []string {
    /* 1. 通过 indexName 获取该 index 的 Index map */
    index := c.indices[indexName]
    names := make([]string, 0, len(index))

    /* 2. 列出该 index 的 Index map 的所有 key，即该 index 的所有索引值 */
    for key := range index {
        names = append(names, key)
    }
    return names
}
```

从上面实现代码可以看出，`Add/Update/Delete/Replace` 这些方法除了更新 `items map` （更新 `key --> object` 的映射）外，还会通过 `updateIndices` 更新 `Index`。

下面接着看 `updateIndices`。

## updateIndices and deleteFromIndices

```
// updateIndices modifies the objects location in the managed indexes, if this is an update, you must provide an oldObj
// updateIndices must be called from a function that already has a lock on the cache
/* newObj 的 key（indexed value）需要在各个 Index 中更新 */
func (c *threadSafeMap) updateIndices(oldObj interface{}, newObj interface{}, key string) error {
    // if we got an old object, we need to remove it before we add it again
    if oldObj != nil {
        c.deleteFromIndices(oldObj, key)
    }

    /* 需要更新所有的 indexer */
    for name, indexFunc := range c.indexers {
        /* 获取 newObj 在该 index 中的 indexed values */
        indexValues, err := indexFunc(newObj)
        if err != nil {
            return err
        }
        /* 获取该 index 的 Index map */
        index := c.indices[name]
        if index == nil {
            index = Index{}
            c.indices[name] = index
        }

        /* 将 key（indexed values）添加到该 index 中 */
        for _, indexValue := range indexValues {
            set := index[indexValue]
            if set == nil {
                set = sets.String{}
                index[indexValue] = set
            }
            set.Insert(key)
        }
    }
    return nil
}

// deleteFromIndices removes the object from each of the managed indexes
// it is intended to be called from a function that already has a lock on the cache
/* obj 的 key（indexed value）需要在各个 Index 中删除 */
func (c *threadSafeMap) deleteFromIndices(obj interface{}, key string) error {
    /* 需要更新所有的 indexer */
    for name, indexFunc := range c.indexers {
        /* 获取 obj 在该 index 中的 indexed values */
        indexValues, err := indexFunc(obj)
        if err != nil {
            return err
        }

        /* 获取该 index 的 Index map */
        index := c.indices[name]
        /* 将 key（indexed values）从该 index 中删除 */
        for _, indexValue := range indexValues {
            if index != nil {
                set := index[indexValue]
                if set != nil {
                    set.Delete(key)
                }
            }
        }
    }
    return nil
}
```



