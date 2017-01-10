delta_fifo、undelta_fifo、expiration_cache 跟前面的 Store 和 FIFO 差不多，不再详细分析。下面简单分析一下 listers。

# StoreToXXXXLister

StoreToXXXXLister 实际上就是一个 Store，唯一的不同就是主要实现了某类特定资源的 list 函数（可能还会根据需要实现了其他的一些函数）。下面举个例子。

## StoreToPodLister

```
//  TODO: generate these classes and methods for all resources of interest using
// a script.  Can use "go generate" once 1.4 is supported by all users.

// StoreToPodLister makes a Store have the List method of the client.PodInterface
// The Store must contain (only) Pods.
//
// Example:
// s := cache.NewStore()
// lw := cache.ListWatch{Client: c, FieldSelector: sel, Resource: "pods"}
// r := cache.NewReflector(lw, &api.Pod{}, s).Run()
// l := StoreToPodLister{s}
// l.List()
type StoreToPodLister struct {
    Store
}

// Please note that selector is filtering among the pods that have gotten into
// the store; there may have been some filtering that already happened before
// that.
//
// TODO: converge on the interface in pkg/client.
func (s *StoreToPodLister) List(selector labels.Selector) (pods []*api.Pod, err error) {
    // TODO: it'd be great to just call
    // s.Pods(api.NamespaceAll).List(selector), however then we'd have to
    // remake the list.Items as a []*api.Pod. So leave this separate for
    // now.
    for _, m := range s.Store.List() {
        pod := m.(*api.Pod)
        if selector.Matches(labels.Set(pod.Labels)) {
            pods = append(pods, pod)
        }
    }
    return pods, nil
}

// Pods is taking baby steps to be more like the api in pkg/client
func (s *StoreToPodLister) Pods(namespace string) storePodsNamespacer {
    return storePodsNamespacer{s.Store, namespace}
}

type storePodsNamespacer struct {
    store     Store
    namespace string
}

// Please note that selector is filtering among the pods that have gotten into
// the store; there may have been some filtering that already happened before
// that.
func (s storePodsNamespacer) List(selector labels.Selector) (pods api.PodList, err error) {
    list := api.PodList{}
    for _, m := range s.store.List() {
        pod := m.(*api.Pod)
        if s.namespace == api.NamespaceAll || s.namespace == pod.Namespace {
            if selector.Matches(labels.Set(pod.Labels)) {
                list.Items = append(list.Items, *pod)
            }
        }
    }
    return list, nil
}

// Exists returns true if a pod matching the namespace/name of the given pod exists in the store.
func (s *StoreToPodLister) Exists(pod *api.Pod) (bool, error) {
    _, exists, err := s.Store.Get(pod)
    if err != nil {
        return false, err
    }
    return exists, nil
}
```

StoreToPodLister 实现了三个方法：

- func (s *StoreToPodLister) List(selector labels.Selector) (pods []*api.Pod, err error)：列出匹配 lable selector 的所有 pod。
- func (s *StoreToPodLister) Pods(namespace string) storePodsNamespacer：以 store 的形式返回属于同一 namespace 的所有 pod，storePodsNamespacer 就是存储属于同一 namespace pod 的。
- func (s *StoreToPodLister) Exists(pod *api.Pod) (bool, error)：判断某个 pod 是否存在。
