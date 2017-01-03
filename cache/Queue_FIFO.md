# Related files

1. pkg/client/cache/fifo.go

# Queue interface

```
// Queue is exactly like a Store, but has a Pop() method too.
type Queue interface {
    Store

    // Pop blocks until it has something to return.
    Pop() interface{}

    // AddIfNotPresent adds a value previously
    // returned by Pop back into the queue as long
    // as nothing else (presumably more recent)
    // has since been added.
    AddIfNotPresent(interface{}) error

    // Return true if the first batch of items has been popped
    HasSynced() bool
}
```

`Queue interface` 也实现了 [Store interface](./Store_Indexer.md)，但是也新增了 `Pop` 等方法。

**Pop() interface{}**：如果 Queue 为空的时候，Pop 方法会阻塞等待。

# FIFO struct

```
// FIFO receives adds and updates from a Reflector, and puts them in a queue for
// FIFO order processing. If multiple adds/updates of a single item happen while
// an item is in the queue before it has been processed, it will only be
// processed once, and when it is processed, the most recent version will be
// processed. This can't be done with a channel.
//
// FIFO solves this use case:
//  * You want to process every object (exactly) once.
//  * You want to process the most recent version of the object when you process it.
//  * You do not want to process deleted objects, they should be removed from the queue.
//  * You do not want to periodically reprocess objects.
// Compare with DeltaFIFO for other use cases.
type FIFO struct {
    lock sync.RWMutex
    cond sync.Cond
    // We depend on the property that items in the set are in the queue and vice versa.
    items map[string]interface{}
    queue []string

    // populated is true if the first batch of items inserted by Replace() has been populated
    // or Delete/Add/Update was called first.
    populated bool
    // initialPopulationCount is the number of items inserted by the first call of Replace()
    initialPopulationCount int

    // keyFunc is used to make the key used for queued item insertion and retrieval, and
    // should be deterministic.
    keyFunc KeyFunc
}

var (
    _ = Queue(&FIFO{}) // FIFO is a Queue
)
```

`FIFO` 接受来自 `Reflector` 的 `Add` 和 `Update` 方法添加对象的操作，并将这些对象放入 `queue` 这个列表中， 以 `First In First Out` 的顺序等待被处理。

如果一个对象已经在 `queue` 中等待处理，而此时又来了该对象的多个 `Add/Update` 操作，这种情况下该对象只会被处理一次，而且只有该对象的最新版本会被处理。其实，`queue` 中存储是的对象的 key，而 `items` 存储的是对象本身，如果一个对象的 key 已经在 `queue` 里了，是不会再往 `queue` 中 append 该对象的 key 了，所以在 `queue` 中的对象只会被处理一次。但是，每次都会更新 `items`，即最新版本的对象会覆盖之前旧的对象。所以待从 `queue` 中取出该 key，处理该 key 对应的对象的时候，都是处理的最新版本的对象。后面分析 `Add` 和 `Pop` 方法的时候我们还会看到。

FIFO 解决的用户场景有：

- 每个对象你只想处理一次
- 当你处理对象的时候，你想处理当前该对象的最新版本
- 你不想处理已删除的对象，应将其从队列中删除
- 你不想周期型的重复处理对象

## Methods of FIFO

```
// Return true if an Add/Update/Delete/AddIfNotPresent are called first,
// or an Update called first but the first batch of items inserted by Replace() has been popped
func (f *FIFO) HasSynced() bool {
    f.lock.Lock()
    defer f.lock.Unlock()
    return f.populated && f.initialPopulationCount == 0
}

// Add inserts an item, and puts it in the queue. The item is only enqueued
// if it doesn't already exist in the set.
func (f *FIFO) Add(obj interface{}) error {
    /* 通过 obj 生成 key */
    id, err := f.keyFunc(obj)
    if err != nil {
        return KeyError{obj, err}
    }
    f.lock.Lock()
    defer f.lock.Unlock()
    f.populated = true
    /*
     * 如果对象的 key 不在 queue 中，就将 key append 到 queue
     * 注意这里 append 到 queue 的是 obj 的 key
     */
    if _, exists := f.items[id]; !exists {
        f.queue = append(f.queue, id)
    }
    /*
     * 每次 Add 操作都保存的是 obj 的最新版本
     * 所以 key 从 queue 中 pop 出来，处理的都是该 key 对应的最新版本的 obj
     */
    f.items[id] = obj
    f.cond.Broadcast()
    return nil
}

// AddIfNotPresent inserts an item, and puts it in the queue. If the item is already
// present in the set, it is neither enqueued nor added to the set.
//
// This is useful in a single producer/consumer scenario so that the consumer can
// safely retry items without contending with the producer and potentially enqueueing
// stale items.
func (f *FIFO) AddIfNotPresent(obj interface{}) error {
    id, err := f.keyFunc(obj)
    if err != nil {
        return KeyError{obj, err}
    }
    f.lock.Lock()
    defer f.lock.Unlock()
    f.populated = true
    if _, exists := f.items[id]; exists {
        return nil
    }

    f.queue = append(f.queue, id)
    f.items[id] = obj
    f.cond.Broadcast()
    return nil
}

// Update is the same as Add in this implementation.
func (f *FIFO) Update(obj interface{}) error {
    return f.Add(obj)
}

// Delete removes an item. It doesn't add it to the queue, because
// this implementation assumes the consumer only cares about the objects,
// not the order in which they were created/added.
/*
 * Delete 操作只是将 obj 从 items map 中删除，应该该实现假设消费者只关心对象本身，
 * 而不考虑该对象被 created/added 的顺序。所以该实现也没有把该 obj 对应的 key 从 queue 中删除
 */
func (f *FIFO) Delete(obj interface{}) error {
    id, err := f.keyFunc(obj)
    if err != nil {
        return KeyError{obj, err}
    }
    f.lock.Lock()
    defer f.lock.Unlock()
    f.populated = true
    delete(f.items, id)
    return err
}

// List returns a list of all the items.
func (f *FIFO) List() []interface{} {
    f.lock.RLock()
    defer f.lock.RUnlock()
    list := make([]interface{}, 0, len(f.items))
    for _, item := range f.items {
        list = append(list, item)
    }
    return list
}

// ListKeys returns a list of all the keys of the objects currently
// in the FIFO.
func (f *FIFO) ListKeys() []string {
    f.lock.RLock()
    defer f.lock.RUnlock()
    list := make([]string, 0, len(f.items))
    for key := range f.items {
        list = append(list, key)
    }
    return list
}

// Get returns the requested item, or sets exists=false.
func (f *FIFO) Get(obj interface{}) (item interface{}, exists bool, err error) {
    key, err := f.keyFunc(obj)
    if err != nil {
        return nil, false, KeyError{obj, err}
    }
    return f.GetByKey(key)
}

// GetByKey returns the requested item, or sets exists=false.
func (f *FIFO) GetByKey(key string) (item interface{}, exists bool, err error) {
    f.lock.RLock()
    defer f.lock.RUnlock()
    item, exists = f.items[key]
    return item, exists, nil
}

// Pop waits until an item is ready and returns it. If multiple items are
// ready, they are returned in the order in which they were added/updated.
// The item is removed from the queue (and the store) before it is returned,
// so if you don't successfully process it, you need to add it back with
// AddIfNotPresent().
func (f *FIFO) Pop() interface{} {
    f.lock.Lock()
    defer f.lock.Unlock()
    for {
        /* 如果 queue 为空，Pop 操作会睡眠等待 */
        for len(f.queue) == 0 {
            f.cond.Wait()
        }
        id := f.queue[0]
        f.queue = f.queue[1:]
        if f.initialPopulationCount > 0 {
            f.initialPopulationCount--
        }
        item, ok := f.items[id]
        /* 如果该 obj 不在 items 中，说明已经被删除，那么从 queue 中取下一个 obj */
        if !ok {
            // Item may have been deleted subsequently.
            continue
        }
        delete(f.items, id)
        return item
    }
}

// Replace will delete the contents of 'f', using instead the given map.
// 'f' takes ownership of the map, you should not reference the map again
// after calling this function. f's queue is reset, too; upon return, it
// will contain the items in the map, in no particular order.
func (f *FIFO) Replace(list []interface{}, resourceVersion string) error {
    items := map[string]interface{}{}
    for _, item := range list {
        key, err := f.keyFunc(item)
        if err != nil {
            return KeyError{item, err}
        }
        items[key] = item
    }

    f.lock.Lock()
    defer f.lock.Unlock()

    if !f.populated {
        f.populated = true
        f.initialPopulationCount = len(items)
    }

    /* 使用新的 items map */
    f.items = items
    /* 清空 queue 队列 */
    f.queue = f.queue[:0]
    /* 重新往 queue 中添加 obj 的 key，此时的 order 就是 obj 在 list 中的 order */
    for id := range items {
        f.queue = append(f.queue, id)
    }
    if len(f.queue) > 0 {
        f.cond.Broadcast()
    }
    return nil
}
```

