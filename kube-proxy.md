<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [kube-proxy 关键代码流程分析](#kube-proxy-%E5%85%B3%E9%94%AE%E4%BB%A3%E7%A0%81%E6%B5%81%E7%A8%8B%E5%88%86%E6%9E%90)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

kubernetes version: v1.7.9

# kube-proxy 关键代码流程分析

cmd/kube-proxy/app/service.go

```
// NewProxyServer returns a new ProxyServer.
func NewProxyServer(config *componentconfig.KubeProxyConfiguration, cleanupAndExit bool, scheme *runtime.Scheme, master string) (*ProxyServer, error) {
    ...

    var proxier proxy.ProxyProvider
    var serviceEventHandler proxyconfig.ServiceHandler
    var endpointsEventHandler proxyconfig.EndpointsHandler

    proxyMode := getProxyMode(string(config.Mode), iptInterface, iptables.LinuxKernelCompatTester{})
    if proxyMode == proxyModeIPTables {
        glog.V(0).Info("Using iptables Proxier.")
        var nodeIP net.IP
        if config.BindAddress != "0.0.0.0" {
            nodeIP = net.ParseIP(config.BindAddress)
        } else {
            nodeIP = getNodeIP(client, hostname)
        }
        if config.IPTables.MasqueradeBit == nil {
            // MasqueradeBit must be specified or defaulted.
            return nil, fmt.Errorf("unable to read IPTables MasqueradeBit from config")
        }

        // TODO this has side effects that should only happen when Run() is invoked.
        proxierIPTables, err := iptables.NewProxier(
            iptInterface,
            utilsysctl.New(),
            execer,
            config.IPTables.SyncPeriod.Duration,
            config.IPTables.MinSyncPeriod.Duration,
            config.IPTables.MasqueradeAll,
            int(*config.IPTables.MasqueradeBit),
            config.ClusterCIDR,
            hostname,
            nodeIP,
            recorder,
            healthzUpdater,
        )
        if err != nil {
            return nil, fmt.Errorf("unable to create proxier: %v", err)
        }
        iptables.RegisterMetrics()
        proxier = proxierIPTables
        serviceEventHandler = proxierIPTables
        endpointsEventHandler = proxierIPTables
        // No turning back. Remove artifacts that might still exist from the userspace Proxier.
        glog.V(0).Info("Tearing down userspace rules.")
        // TODO this has side effects that should only happen when Run() is invoked.
        userspace.CleanupLeftovers(iptInterface)
    } else {
        glog.V(0).Info("Using userspace Proxier.")
        if goruntime.GOOS == "windows" {
            ...
        } else {
            // This is a proxy.LoadBalancer which NewProxier needs but has methods we don't need for
            // our config.EndpointsConfigHandler.
            loadBalancer := userspace.NewLoadBalancerRR()
            // set EndpointsConfigHandler to our loadBalancer
            endpointsEventHandler = loadBalancer

            // TODO this has side effects that should only happen when Run() is invoked.
            proxierUserspace, err := userspace.NewProxier(
                loadBalancer,
                net.ParseIP(config.BindAddress),
                iptInterface,
                execer,
                *utilnet.ParsePortRangeOrDie(config.PortRange),
                config.IPTables.SyncPeriod.Duration,
                config.IPTables.MinSyncPeriod.Duration,
                config.UDPIdleTimeout.Duration,
            )
            if err != nil {
                return nil, fmt.Errorf("unable to create proxier: %v", err)
            }
            serviceEventHandler = proxierUserspace
            proxier = proxierUserspace
        }
        // Remove artifacts from the pure-iptables Proxier, if not on Windows.
        if goruntime.GOOS != "windows" {
            glog.V(0).Info("Tearing down pure-iptables proxy rules.")
            // TODO this has side effects that should only happen when Run() is invoked.
            iptables.CleanupLeftovers(iptInterface)
        }
    }

    // Add iptables reload function, if not on Windows.
    if goruntime.GOOS != "windows" {
        iptInterface.AddReloadFunc(proxier.Sync)
    }

    nodeRef := &clientv1.ObjectReference{
        Kind:      "Node",
        Name:      hostname,
        UID:       types.UID(hostname),
        Namespace: "",
    }

    return &ProxyServer{
        Client:                 client,
        EventClient:            eventClient,
        IptInterface:           iptInterface,
        Proxier:                proxier,
        Broadcaster:            eventBroadcaster,
        Recorder:               recorder,
        ConntrackConfiguration: config.Conntrack,
        Conntracker:            &realConntracker{},
        ProxyMode:              proxyMode,
        NodeRef:                nodeRef,
        MetricsBindAddress:     config.MetricsBindAddress,
        EnableProfiling:        config.EnableProfiling,
        OOMScoreAdj:            config.OOMScoreAdj,
        ResourceContainer:      config.ResourceContainer,
        ConfigSyncPeriod:       config.ConfigSyncPeriod.Duration,
        ServiceEventHandler:    serviceEventHandler,
        EndpointsEventHandler:  endpointsEventHandler,
        HealthzServer:          healthzServer,
    }, nil
}
```

这里比较关键的是三个变量：`proxier`，`serviceEventHandler`，`endpointsEventHandler`。

iptabels 模式下，这三个变量的值是一样的：

```
        proxier = proxierIPTables
        serviceEventHandler = proxierIPTables
        endpointsEventHandler = proxierIPTables
```

而 userspace 模式下则为：

```
        endpointsEventHandler = loadBalancer
        serviceEventHandler = proxierUserspace
        proxier = proxierUserspace
```

下面主要针对 iptable 模式进行分析。

另外还要特别关注一下 NewProxier() 函数：

// pkg/proxy/iptables/proxier.go

```
// NewProxier returns a new Proxier given an iptables Interface instance.
// Because of the iptables logic, it is assumed that there is only a single Proxier active on a machine.
// An error will be returned if iptables fails to update or acquire the initial lock.
// Once a proxier is created, it will keep iptables up to date in the background and
// will not terminate if a particular iptables call fails.
func NewProxier(ipt utiliptables.Interface,
    sysctl utilsysctl.Interface,
    exec utilexec.Interface,
    syncPeriod time.Duration,
    minSyncPeriod time.Duration,
    masqueradeAll bool,
    masqueradeBit int,
    clusterCIDR string,
    hostname string,
    nodeIP net.IP,
    recorder record.EventRecorder,
    healthzServer healthcheck.HealthzUpdater,
) (*Proxier, error) {
    ...

    proxier := &Proxier{
        portsMap:                 make(map[localPort]closeable),
        serviceMap:               make(proxyServiceMap),
        serviceChanges:           newServiceChangeMap(),
        endpointsMap:             make(proxyEndpointsMap),
        endpointsChanges:         newEndpointsChangeMap(hostname),
        iptables:                 ipt,
        masqueradeAll:            masqueradeAll,
        masqueradeMark:           masqueradeMark,
        exec:                     exec,
        clusterCIDR:              clusterCIDR,
        hostname:                 hostname,
        nodeIP:                   nodeIP,
        portMapper:               &listenPortOpener{},
        recorder:                 recorder,
        healthChecker:            healthChecker,
        healthzServer:            healthzServer,
        precomputedProbabilities: make([]string, 0, 1001),
        iptablesData:             bytes.NewBuffer(nil),
        filterChains:             bytes.NewBuffer(nil),
        filterRules:              bytes.NewBuffer(nil),
        natChains:                bytes.NewBuffer(nil),
        natRules:                 bytes.NewBuffer(nil),
    }
    burstSyncs := 2
    glog.V(3).Infof("minSyncPeriod: %v, syncPeriod: %v, burstSyncs: %d", minSyncPeriod, syncPeriod, burstSyncs)
    proxier.syncRunner = async.NewBoundedFrequencyRunner("sync-runner", proxier.syncProxyRules, minSyncPeriod, syncPeriod, burstSyncs)
    return proxier, nil
}
```

proxier.syncRunner.Run() 函数最后执行的就是 `proxier.syncProxyRules`。

ProxyServer 的运行逻辑如下：

```
// Run runs the specified ProxyServer.  This should never exit (unless CleanupAndExit is set).
func (s *ProxyServer) Run() error {
    ...

    informerFactory := informers.NewSharedInformerFactory(s.Client, s.ConfigSyncPeriod)

    // Create configs (i.e. Watches for Services and Endpoints)
    // Note: RegisterHandler() calls need to happen before creation of Sources because sources
    // only notify on changes, and the initial update (on process start) may be lost if no handlers
    // are registered yet.
    serviceConfig := proxyconfig.NewServiceConfig(informerFactory.Core().InternalVersion().Services(), s.ConfigSyncPeriod)
    serviceConfig.RegisterEventHandler(s.ServiceEventHandler)
    go serviceConfig.Run(wait.NeverStop)

    endpointsConfig := proxyconfig.NewEndpointsConfig(informerFactory.Core().InternalVersion().Endpoints(), s.ConfigSyncPeriod)
    endpointsConfig.RegisterEventHandler(s.EndpointsEventHandler)
    go endpointsConfig.Run(wait.NeverStop)

    // This has to start after the calls to NewServiceConfig and NewEndpointsConfig because those
    // functions must configure their shared informer event handlers first.
    go informerFactory.Start(wait.NeverStop)

    // Birth Cry after the birth is successful
    s.birthCry()

    // Just loop forever for now...
    s.Proxier.SyncLoop()
    return nil
}
```

Run() 函数里面主要包含三层 sync 逻辑：serviceConfig／endpointsConfig 两层 sync 逻辑，ProxyServer 一层 sync 逻辑。endpointConfig 跟 serviceConfig 代码逻辑完全一样，这里只分析 serviceConfig。

**serviceConfig 两层 sync 逻辑**

- serviceConfig just one sync 逻辑

serviceConfig 由 serviceInformer 改造而来，第一层 sync 逻辑由 serviceConfig 触发的 just one sync 逻辑：ServiceConfig.Run()，即首次 service list 完毕之后，主动调用 eventHandler 触发一次仅且一次 sync 逻辑：

// pkg/proxy/config/config.go

```
    // ServiceConfig tracks a set of service configurations.
    // It accepts "set", "add" and "remove" operations of services via channels, and invokes registered handlers on change.
    type ServiceConfig struct {
        lister        listers.ServiceLister
        listerSynced  cache.InformerSynced
        eventHandlers []ServiceHandler
    }

    // NewServiceConfig creates a new ServiceConfig.
    func NewServiceConfig(serviceInformer coreinformers.ServiceInformer, resyncPeriod time.Duration) *ServiceConfig {
        result := &ServiceConfig{
            lister:       serviceInformer.Lister(),
            listerSynced: serviceInformer.Informer().HasSynced,
        }

        serviceInformer.Informer().AddEventHandlerWithResyncPeriod(
            cache.ResourceEventHandlerFuncs{
                AddFunc:    result.handleAddService,
                UpdateFunc: result.handleUpdateService,
                DeleteFunc: result.handleDeleteService,
            },
            resyncPeriod,
        )

        return result
    }

    // Run starts the goroutine responsible for calling
    // registered handlers.
    func (c *ServiceConfig) Run(stopCh <-chan struct{}) {
        defer utilruntime.HandleCrash()

        glog.Info("Starting service config controller")
        defer glog.Info("Shutting down service config controller")

        if !controller.WaitForCacheSync("service config", stopCh, c.listerSynced) {
            return
        }

        for i := range c.eventHandlers {
            glog.V(3).Infof("Calling handler.OnServiceSynced()")
            c.eventHandlers[i].OnServiceSynced()
        }

        <-stopCh
    }
```

// pkg/proxy/iptables/proxier.go

```
func (proxier *Proxier) OnServiceSynced() {
    proxier.mu.Lock()
    proxier.servicesSynced = true
    proxier.setInitialized(proxier.servicesSynced && proxier.endpointsSynced)
    proxier.mu.Unlock()

    // Sync unconditionally - this is called once per lifetime.
    proxier.syncProxyRules()
}
```

- serviceConfig 第二层 sync 逻辑

ServiceConfig.Run() 最后都 block 在 `<-stopCh`，该函数不退出，因为 serviceInformer 通过 list & watch 方式一直在侦听 service 的变化，一旦侦听到变化就调用 ServiceConfig 的 EventHandlerFuncs 处理：

// pkg/proxy/config/config.go

```
func (c *ServiceConfig) handleAddService(obj interface{}) {
    service, ok := obj.(*api.Service)
    if !ok {
        utilruntime.HandleError(fmt.Errorf("unexpected object type: %v", obj))
        return
    }
    for i := range c.eventHandlers {
        glog.V(4).Infof("Calling handler.OnServiceAdd")
        c.eventHandlers[i].OnServiceAdd(service)
    }
}

func (c *ServiceConfig) handleUpdateService(oldObj, newObj interface{}) {
    oldService, ok := oldObj.(*api.Service)
    if !ok {
        utilruntime.HandleError(fmt.Errorf("unexpected object type: %v", oldObj))
        return
    }
    service, ok := newObj.(*api.Service)
    if !ok {
        utilruntime.HandleError(fmt.Errorf("unexpected object type: %v", newObj))
        return
    }
    for i := range c.eventHandlers {
        glog.V(4).Infof("Calling handler.OnServiceUpdate")
        c.eventHandlers[i].OnServiceUpdate(oldService, service)
    }
}

func (c *ServiceConfig) handleDeleteService(obj interface{}) {
    service, ok := obj.(*api.Service)
    if !ok {
        tombstone, ok := obj.(cache.DeletedFinalStateUnknown)
        if !ok {
            utilruntime.HandleError(fmt.Errorf("unexpected object type: %v", obj))
            return
        }
        if service, ok = tombstone.Obj.(*api.Service); !ok {
            utilruntime.HandleError(fmt.Errorf("unexpected object type: %v", obj))
            return
        }
    }
    for i := range c.eventHandlers {
        glog.V(4).Infof("Calling handler.OnServiceDelete")
        c.eventHandlers[i].OnServiceDelete(service)
    }
}
```

// pkg/proxy/iptables/proxier.go

```
func (proxier *Proxier) OnServiceAdd(service *api.Service) {
    namespacedName := types.NamespacedName{Namespace: service.Namespace, Name: service.Name}
    if proxier.serviceChanges.update(&namespacedName, nil, service) && proxier.isInitialized() {
        proxier.syncRunner.Run()
    }
}

func (proxier *Proxier) OnServiceUpdate(oldService, service *api.Service) {
    namespacedName := types.NamespacedName{Namespace: service.Namespace, Name: service.Name}
    if proxier.serviceChanges.update(&namespacedName, oldService, service) && proxier.isInitialized() {
        proxier.syncRunner.Run()
    }
}

func (proxier *Proxier) OnServiceDelete(service *api.Service) {
    namespacedName := types.NamespacedName{Namespace: service.Namespace, Name: service.Name}
    if proxier.serviceChanges.update(&namespacedName, service, nil) && proxier.isInitialized() {
        proxier.syncRunner.Run()
    }
}
```

这些 handler 就是在 ProxyServer.Run() 中通过 serviceConfig.RegisterEventHandler() 添加的：

// pkg/proxy/config/config.go

```
// RegisterEventHandler registers a handler which is called on every service change.
func (c *ServiceConfig) RegisterEventHandler(handler ServiceHandler) {
    c.eventHandlers = append(c.eventHandlers, handler)
}
```

通过之前的分析，结合这些 handler 的执行代码来看，serviceConfig 的两层 sync 逻辑最后都落到 `proxier.syncRunner.Run()` 函数上，而 `proxier.syncRunner.Run()` 最终触发 `proxier.syncRunner.Loop()`，而 `proxier.syncRunner.Loop()` 就 wait 在 `ProxyServe.Run()` 中，这点我们在`ProxyServer 一层 sync 逻辑`这一节详细分析。

// pkg/util/async/bounded_frequency_runner.go

```
// Run the function as soon as possible.  If this is called while Loop is not
// running, the call may be deferred indefinitely.
// If there is already a queued request to call the underlying function, it
// may be dropped - it is just guaranteed that we will try calling the
// underlying function as soon as possible starting from now.
func (bfr *BoundedFrequencyRunner) Run() {
    // If it takes a lot of time to run the underlying function, noone is really
    // processing elements from <run> channel. So to avoid blocking here on the
    // putting element to it, we simply skip it if there is already an element
    // in it.
    select {
    case bfr.run <- struct{}{}:
    default:
    }
}
```

另外要注意的就是这些 handler 里面的 proxier.serviceChanges.update() 函数，该函数根据变化的 service 更新 serviceChangeMap/proxyServiceMap：

// pkg/proxy/iptables/proxier.go

```
func (scm *serviceChangeMap) update(namespacedName *types.NamespacedName, previous, current *api.Service) bool {
    scm.lock.Lock()
    defer scm.lock.Unlock()

    change, exists := scm.items[*namespacedName]
    if !exists {
        change = &serviceChange{}
        change.previous = serviceToServiceMap(previous)
        scm.items[*namespacedName] = change
    }
    change.current = serviceToServiceMap(current)
    if reflect.DeepEqual(change.previous, change.current) {
        delete(scm.items, *namespacedName)
    }
    return len(scm.items) > 0
}

// Translates single Service object to proxyServiceMap.
//
// NOTE: service object should NOT be modified.
func serviceToServiceMap(service *api.Service) proxyServiceMap {
    if service == nil {
        return nil
    }
    svcName := types.NamespacedName{Namespace: service.Namespace, Name: service.Name}
    if shouldSkipService(svcName, service) {
        return nil
    }

    serviceMap := make(proxyServiceMap)
    for i := range service.Spec.Ports {
        servicePort := &service.Spec.Ports[i]
        svcPortName := proxy.ServicePortName{NamespacedName: svcName, Port: servicePort.Name}
        serviceMap[svcPortName] = newServiceInfo(svcPortName, servicePort, service)
    }
    return serviceMap
}
```

**ProxyServer 一层 sync 逻辑**

`ProxyServe.Run()` 函数调用 `s.Proxier.SyncLoop()`，并 wait 在 `proxier.syncRunner.Loop()` 上：

// pkg/proxy/iptables/proxier.go

```
// SyncLoop runs periodic work.  This is expected to run as a goroutine or as the main loop of the app.  It does not return.
func (proxier *Proxier) SyncLoop() {
    // Update healthz timestamp at beginning in case Sync() never succeeds.
    if proxier.healthzServer != nil {
        proxier.healthzServer.UpdateTimestamp()
    }
    proxier.syncRunner.Loop(wait.NeverStop)
}
```

// pkg/util/async/bounded_frequency_runner.go

```
// Loop handles the periodic timer and run requests.  This is expected to be
// called as a goroutine.
func (bfr *BoundedFrequencyRunner) Loop(stop <-chan struct{}) {
    glog.V(3).Infof("%s Loop running", bfr.name)
    bfr.timer.Reset(bfr.maxInterval)
    for {
        select {
        case <-stop:
            bfr.stop()
            glog.V(3).Infof("%s Loop stopping", bfr.name)
            return
        case <-bfr.timer.C():
            bfr.tryRun()
        case <-bfr.run:
            bfr.tryRun()
        }
    }
}

// assumes the lock is not held
func (bfr *BoundedFrequencyRunner) tryRun() {
    ...

    if bfr.limiter.TryAccept() {
        // We're allowed to run the function right now.
        bfr.fn()
        bfr.lastRun = bfr.timer.Now()
        bfr.timer.Stop()
        bfr.timer.Reset(bfr.maxInterval)
        glog.V(3).Infof("%s: ran, next possible in %v, periodic in %v", bfr.name, bfr.minInterval, bfr.maxInterval)
        return
    }

    ...
}
```

`proxier.syncRunner.Loop()`  将 wait 在两个事件上：

1. `bfr.run` channel：serviceConfig/endpointConfig 两层 sync 通过 `bfr.run` channel 触发 Loop 执行 tryRun()。
2. `bfr.timer.C()` channel：根据 ProxyServer 中配置的超时时间，ProxyServer 这层通过 `bfr.timer.C()` 周期性的触发 Loop 执行 tryRun()。这个周期性 sync 是非常有作用的，能够每隔一段时间保证当前 service/endpoint 状态同步到 iptables，而防止 iptables 出现意外/人为的改变。

而在 tryRun() 中执行的函数就是：`proxier.syncProxyRules`，该函数将获取到的 service/endpoint 信息翻译成 ipatbles 规则。

**总结**

从上面的分析来看，ProxyServer.Run() 函数中的三层 sync 逻辑如下：

1. serviceConfig/endpointConfig 等待第一次 service & endpoint list 完毕后执行一次且只执行一次 sync
2. serviceInformer/endpointInformer watch 到 service/endpoint 变化会触发一次 sync
3. ProxyServer 周期性执行 sync

**proxier.syncProxyRules**

`proxier.syncProxyRules` 主要根据 `proxyServiceMap` 和 `proxyEndpointsMap` 信息来更新 ipatbles 规则，而 `proxyServiceMap` 和 `proxyEndpointsMap` 的更新发生在上面分析的 `OnServiceAdd`，`OnServiceUpdate`，`OnServiceDelete`，`OnEndpointsAdd`，`OnEndpointsUpdate`，`OnEndpointsDelete` 函数中。
