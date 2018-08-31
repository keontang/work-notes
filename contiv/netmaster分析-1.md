# netmaster 框架代码分析

## netmaster 参数分析

```
NAME:
   netmaster - Contiv netmaster service

USAGE:
   netmaster [global options] command [command options] [arguments...]

VERSION:

Version: <netplugin-version>
GitCommit: <netplugin-commit-sha>
BuildTime: <netplugin-build-time>


COMMANDS:
     help, h  Shows a list of commands or help for one command

GLOBAL OPTIONS:
   --consul-endpoints value, --consul value                 a comma-delimited list of netmaster consul endpoints [$CONTIV_NETMASTER_CONSUL_ENDPOINTS]
   --etcd-endpoints value, --etcd value                     a comma-delimited list of netmaster etcd endpoints (default: http://127.0.0.1:2379) [$CONTIV_NETMASTER_ETCD_ENDPOINTS]
   --external-address value, --listen-url value             set netmaster external address to listen on, used for general API service (default: "0.0.0.0:9999") [$CONTIV_NETMASTER_EXTERNAL_ADDRESS]
   --fwdmode value, --forward-mode value                    set netmaster forwarding network mode, options: [bridge, routing] [$CONTIV_NETMASTER_FORWARD_MODE]
   --infra value, --infra-type value                        set netmaster infra type, options [aci, default] (default: "default") [$CONTIV_NETMASTER_INFRA]
   --internal-address value, --control-url value            set netmaster internal address to listen on, used for RPC and leader election (default: <host-ip-from-local-resolver>:<port-of-external-address>) [$CONTIV_NETMASTER_INTERNAL_ADDRESS]
   --log-level value                                        set netmaster log level, options: [DEBUG, INFO, WARN, ERROR] (default: "INFO") [$CONTIV_NETMASTER_LOG_LEVEL]
   --mode value, --plugin-mode value, --cluster-mode value  set netmaster mode, options: [docker, kubernetes, swarm-mode] [$CONTIV_NETMASTER_MODE]
   --name value, --plugin-name value                        set netmaster plugin name for docker v2 plugin (default: "netplugin") [$CONTIV_NETMASTER_PLUGIN_NAME]
   --netmode value, --network-mode value                    set netmaster network mode, options: [vlan, vxlan] [$CONTIV_NETMASTER_NET_MODE]
   --syslog-url value                                       set netmaster syslog url in format protocol://ip:port (default: "udp://127.0.0.1:514") [$CONTIV_NETMASTER_SYSLOG_URL]
   --use-json-log, --json-log                               set netmaster log format to json if this flag is provided [$CONTIV_NETMASTER_USE_JSON_LOG]
   --use-syslog, --syslog                                   set netmaster send log to syslog if this flag is provided [$CONTIV_NETMASTER_USE_SYSLOG]
   --help, -h                                               show help
   --version, -v                                            print the version
```

## 相关数据结构

**netmaster/daemon/daemon.go**

// MasterDaemon runs the daemon FSM
type MasterDaemon struct {
    // Public state
    ListenURL          string // URL where netmaster listens for ext requests
    ControlURL         string // URL where netmaster listens for ctrl pkts
    ClusterStoreDriver string // state store driver name
    ClusterStoreURL    string // state store endpoint
    ClusterMode        string // cluster scheduler used docker/kubernetes/mesos etc
    NetworkMode        string // network mode (vlan or vxlan)
    NetForwardMode     string // forwarding mode (bridge or routing)
    NetInfraType       string // infra type (aci or default)

    // Private state
    currState        string                          // Current state of the daemon
    apiController    *objApi.APIController           // API controller for contiv model
    stateDriver      core.StateDriver                // KV store
    resmgr           *resources.StateResourceManager // state resource manager
    objdbClient      objdb.API                       // Objdb client
    ofnetMaster      *ofnet.OfnetMaster              // Ofnet master instance
    listenerMutex    sync.Mutex                      // Mutex for HTTP listener
    stopLeaderChan   chan bool                       // Channel to stop the leader listener
    stopFollowerChan chan bool                       // Channel to stop the follower listener
}


## 程序入口

**netmaster/main.go**

func main() {
    app := cli.NewApp()
    app.Action = func(ctx *cli.Context) error {
        // validate netmaster 命令行参数，构建 MasterDaemon 实例
        netmaster, err := initNetMaster(ctx)
        // 启动 master daemon 实例
        startNetMaster(netmaster)
        return nil
    }
    app.Run(os.Args)
}

## 初始化 MasterDaemon 实例

**netmaster/daemon/daemon.go**

func initNetMaster(ctx *cli.Context) (*daemon.MasterDaemon, error) {
    // 1. validate and init logging
    if err := utils.InitLogging(binName, ctx); err != nil {
        return nil, err
    }

    // 2. validate network configs
    netConfigs, err := utils.ValidateNetworkOptions(binName, ctx)

    // 3. validate db configs
    dbConfigs, err := utils.ValidateDBOptions(binName, ctx)

    // 4. set v2 plugin name if it's set
    pluginName := ctx.String("name")
    if netConfigs.Mode == core.Docker || netConfigs.Mode == core.SwarmMode {
        logrus.Infof("Using netmaster docker v2 plugin name: %s", pluginName)
        docknet.UpdateDockerV2PluginName(pluginName, pluginName)
    } else {
        logrus.Infof("Ignoring netmaster docker v2 plugin name: %s (netmaster mode: %s)", pluginName, netConfigs.Mode)
    }

    // 5. set plugin listen addresses
    externalAddress := ctx.String("external-address")
    netutils.ValidateBindAddress(externalAddress)

    internalAddress := ctx.String("internal-address")
    netutils.ValidateBindAddress(internalAddress)

    // 6. validate infra type
    infra := strings.ToLower(ctx.String("infra"))
    switch infra {
    case "aci", "default":
        logrus.Infof("Using netmaster infra type: %s", infra)
    default:
        return nil, fmt.Errorf("Unknown netmaster infra type: %s", infra)
    }

    return &daemon.MasterDaemon{
        ListenURL:          externalAddress,
        ControlURL:         internalAddress,
        ClusterStoreDriver: dbConfigs.StoreDriver,
        ClusterStoreURL:    dbConfigs.StoreURL, //TODO: support more than one url
        ClusterMode:        netConfigs.Mode,
        NetworkMode:        netConfigs.NetworkMode,
        NetForwardMode:     netConfigs.ForwardMode,
        NetInfraType:       infra,
    }, nil
}

## 启动 netmaster daemon 实例

**netmaster/main.go**

func startNetMaster(netmaster *daemon.MasterDaemon) {
    // initialize master daemon
    netmaster.Init()
    // start monitoring services
    netmaster.InitServices()
    // Run daemon FSM
    netmaster.RunMasterFsm()
}

## 初始化 netmaster daemon

1. 设置 clusterMode
2. 创建基于 etcd/consul 存储的 client
3. 创建封装了 etcd/consul client 的 state resource manager
4. 创建封装了 etcd/consul client 的 objdb

**netmaster/daemon/daemon.go**

stateDriver 和 objdbClient 都用的同一个 kv store.

// Init initializes the master daemon
func (d *MasterDaemon) Init() {
    // set cluster mode
    err := master.SetClusterMode(d.ClusterMode)

    // initialize state driver
    d.stateDriver, err = utils.NewStateDriver(d.ClusterStoreDriver, &core.InstanceInfo{DbURL: d.ClusterStoreURL})

    // Initialize resource manager
    d.resmgr, err = resources.NewStateResourceManager(d.stateDriver)

    // Create an objdb client
    d.objdbClient, err = objdb.InitClient(d.ClusterStoreDriver, []string{d.ClusterStoreURL})
}

## 初始化 netmaster daemon 的 watch 服务

实际上，目前什么事情都没做。

**netmaster/daemon/daemon.go**

// InitServices init watch services
func (d *MasterDaemon) InitServices() {
    if d.ClusterMode == "kubernetes" {
        isLeader := func() bool {
            return d.currState == "leader"
        }
        // 目前只 watch 和处理 k8s networkpolicy
        // 但是从处理代码来看，对 watch 到的 k8s networkpolicy 也什么事情都不做
        networkpolicy.InitK8SServiceWatch(d.ControlURL, isLeader)
    }
}

**netmaster/k8snetwork/networkpolicy.go**

// InitK8SServiceWatch monitor k8s services
func InitK8SServiceWatch(listenAddr string, isLeader func() bool) error {
    npLog = log.WithField("k8s", "netpolicy")

    npLog.Infof("Create contiv client at http://%s", listenAddr)
    contivClient, err := client.NewContivClient("http://" + listenAddr)
    if err != nil {
        npLog.Errorf("failed to create contivclient %s", err)
        return err
    }

    k8sClientSet, err := k8sutils.SetUpK8SClient()
    if err != nil {
        npLog.Fatalf("failed to init K8S client, %v", err)
        return err
    }
    kubeNet := k8sContext{contivClient: contivClient, k8sClientSet: k8sClientSet, isLeader: isLeader}

    go kubeNet.handleK8sEvents()
    return nil
}

func (k8sNet *k8sContext) handleK8sEvents() {
    for k8sNet.isLeader() != true {
        time.Sleep(time.Second * 10)
    }

    errCh := make(chan error)
    for {
        go k8sNet.watchK8sEvents(errCh)

        // wait for error from api server
        errMsg := <-errCh
        npLog.Errorf("%s", errMsg)
        npLog.Warnf("restarting k8s event watch")
        time.Sleep(time.Second * 5)
    }
}

func (k8sNet *k8sContext) watchK8sEvents(errChan chan error) {
    var selCase []reflect.SelectCase

    // wait to become leader
    for k8sNet.isLeader() != true {
        time.Sleep(time.Millisecond * 100)
    }

    npWatch, err := k8sNet.k8sClientSet.Networking().NetworkPolicies("").Watch(meta_v1.ListOptions{})
    if err != nil {
        errChan <- fmt.Errorf("failed to watch network policy, %s", err)
        return
    }

    selCase = append(selCase, reflect.SelectCase{Dir: reflect.SelectRecv,
        Chan: reflect.ValueOf(npWatch.ResultChan())})

    for {
        _, recVal, ok := reflect.Select(selCase)
        if !ok {
            // channel closed, trigger restart
            errChan <- fmt.Errorf("channel closed to k8s api server")
            return
        }

        if k8sNet.isLeader() != true {
            continue
        }

        if event, ok := recVal.Interface().(watch.Event); ok {
            k8sNet.processK8sEvent(event.Type, event.Object)
        }
        // ignore other events
    }
}

func (k8sNet *k8sContext) processK8sEvent(opCode watch.EventType, eventObj interface{}) {
    if k8sNet.isLeader() != true {
        return
    }
    switch objType := eventObj.(type) {

    case *v1.NetworkPolicy:
        k8sNet.processK8sNetworkPolicy(opCode, objType)
    }
}

实际上，当前版本，contiv 对 watch 到的 k8s networkpolicy 什么事情都不做：

func (k8sNet *k8sContext) processK8sNetworkPolicy(opCode watch.EventType, np *v1.NetworkPolicy) {
    if np.Namespace == "kube-system" { // not applicable for system namespace
        return
    }

    npLog.Infof("process [%s] network policy  %+v", opCode, np)

    switch opCode {
    case watch.Added, watch.Modified:
    case watch.Deleted:
    }
}

## netmaster daemon FSM 启动流程

**netmaster/daemon/daemon.go**

// RunMasterFsm runs netmaster FSM
func (d *MasterDaemon) RunMasterFsm() {
    var err error

    masterURL := strings.Split(d.ControlURL, ":")
    masterIP, masterPort := masterURL[0], masterURL[1]
    if len(masterURL) != 2 {
        log.Fatalf("Invalid netmaster URL")
    }

    // create new ofnet master
    d.ofnetMaster = ofnet.NewOfnetMaster(masterIP, ofnet.OFNET_MASTER_PORT)
    if d.ofnetMaster == nil {
        log.Fatalf("Error creating ofnet master")
    }

    // Register all existing netplugins in the background
    go d.agentDiscoveryLoop()

    // Create the lock
    leaderLock, err = d.objdbClient.NewLock("netmaster/leader", masterIP+":"+masterPort, leaderLockTTL)
    if err != nil {
        log.Fatalf("Could not create leader lock. Err: %v", err)
    }

    // Try to acquire the lock
    err = leaderLock.Acquire(0)
    if err != nil {
        // We dont expect any error during acquire.
        log.Fatalf("Error while acquiring lock. Err: %v", err)
    }

    // Initialize the stop channel
    d.stopLeaderChan = make(chan bool, 1)
    d.stopFollowerChan = make(chan bool, 1)

    // set current state
    d.currState = "follower"

    // Start off being a follower
    go d.runFollower()

    // Main run loop waiting on leader lock
    for {
        // Wait for lock events
        select {
        case event := <-leaderLock.EventChan():
            if event.EventType == objdb.LockAcquired {
                log.Infof("Leader lock acquired")

                d.becomeLeader()
            } else if event.EventType == objdb.LockLost {
                log.Infof("Leader lock lost. Becoming follower")

                d.becomeFollower()
            }
        }
    }
}

// Find all netplugin nodes and add them to ofnet master
func (d *MasterDaemon) agentDiscoveryLoop() {

    // Create channels for watch thread
    agentEventCh := make(chan objdb.WatchServiceEvent, 1)
    watchStopCh := make(chan bool, 1)

    // Start a watch on netplugin service
    err := d.objdbClient.WatchService("netplugin", agentEventCh, watchStopCh)

    for {
        agentEv := <-agentEventCh
        log.Debugf("Received netplugin watch event: %+v", agentEv)
        // build host info
        nodeInfo := ofnet.OfnetNode{
            HostAddr: agentEv.ServiceInfo.HostAddr,
            HostPort: uint16(agentEv.ServiceInfo.Port),
        }

        if agentEv.EventType == objdb.WatchServiceEventAdd {
            err = d.ofnetMaster.AddNode(nodeInfo)
            if err != nil {
                log.Errorf("Error adding node %v. Err: %v", nodeInfo, err)
            }
        } else if agentEv.EventType == objdb.WatchServiceEventDel {
            var res bool
            log.Infof("Unregister node %+v", nodeInfo)
            d.ofnetMaster.UnRegisterNode(&nodeInfo, &res)

            go d.startDeferredCleanup(nodeInfo, agentEv.ServiceInfo.Hostname)
        }

        // Dont process next peer event for another 100ms
        time.Sleep(100 * time.Millisecond)
    }
}

// runFollower runs the follower FSM loop
func (d *MasterDaemon) runFollower() {
    router := mux.NewRouter()
    // slaveProxyHandler 将请求代理到当前 master
    router.PathPrefix("/").HandlerFunc(slaveProxyHandler)

    // Register netmaster service
    d.registerService()

    // just wait on stop channel
    log.Infof("Listening in follower mode")
    d.startListeners(router, d.stopFollowerChan)

    log.Info("Exiting follower mode")
}

// becomeLeader changes daemon FSM state to master
func (d *MasterDaemon) becomeLeader() {
    // ask listener to stop
    d.stopFollowerChan <- true

    // set current state
    d.currState = "leader"

    // Run the HTTP listener
    go d.runLeader()
}

// becomeFollower changes FSM state to follower
func (d *MasterDaemon) becomeFollower() {
    // ask listener to stop
    d.stopLeaderChan <- true
    time.Sleep(time.Second)

    // set current state
    d.currState = "follower"

    // run follower loop
    go d.runFollower()
}

## leader netmaster 处理逻辑

**netmaster/daemon/daemon.go**

// runLeader runs leader loop
func (d *MasterDaemon) runLeader() {
    router := mux.NewRouter()

    // Create a new api controller
    apiConfig := &objApi.APIControllerConfig{
        NetForwardMode: d.NetForwardMode,
        NetInfraType:   d.NetInfraType,
    }
    // 创建 apicontroller 实例
    d.apiController = objApi.NewAPIController(router, d.objdbClient, apiConfig)

    //Restore state from clusterStore
    d.restoreCache()

    // Register netmaster service
    d.registerService()

    // initialize policy manager
    mastercfg.InitPolicyMgr(d.stateDriver, d.ofnetMaster)

    // setup HTTP routes
    d.registerRoutes(router)

    // 启动 netmaster 服务
    d.startListeners(router, d.stopLeaderChan)

    log.Infof("Exiting Leader mode")
}


### 创建 apicontroller 实例

**objApi/apiController.go**

// NewAPIController creates a new controller
func NewAPIController(router *mux.Router, objdbClient objdb.API, configs *APIControllerConfig) *APIController {
    ctrler := new(APIController)
    ctrler.router = router
    ctrler.objdbClient = objdbClient

    // init modeldb
    modeldb.Init(&objdbClient)

    // initialize the model objects
    contivModel.Init()

    // Register Callbacks
    contivModel.RegisterGlobalCallbacks(ctrler)
    contivModel.RegisterAppProfileCallbacks(ctrler)
    contivModel.RegisterEndpointGroupCallbacks(ctrler)
    contivModel.RegisterNetworkCallbacks(ctrler)
    contivModel.RegisterPolicyCallbacks(ctrler)
    contivModel.RegisterRuleCallbacks(ctrler)
    contivModel.RegisterTenantCallbacks(ctrler)
    contivModel.RegisterBgpCallbacks(ctrler)
    contivModel.RegisterServiceLBCallbacks(ctrler)
    contivModel.RegisterExtContractsGroupCallbacks(ctrler)
    contivModel.RegisterEndpointCallbacks(ctrler)
    contivModel.RegisterNetprofileCallbacks(ctrler)
    contivModel.RegisterAciGwCallbacks(ctrler)
    // Register routes
    //  设置 netmaster restful api 处理函数
    contivModel.AddRoutes(router)

    // Init global state from config
    initGlobalConfigs(configs)

    // Add default tenant if it doesnt exist
    tenant := contivModel.FindTenant("default")
    if tenant == nil {
        log.Infof("Creating default tenant")
        err := contivModel.CreateTenant(&contivModel.Tenant{
            Key:        "default",
            TenantName: "default",
        })
        if err != nil {
            log.Fatalf("Error creating default tenant. Err: %v", err)
        }
    }

    return ctrler
}

**contivmodel/contivModel.go**

// Add all routes for REST handlers
func AddRoutes(router *mux.Router) {
    var route, listRoute, inspectRoute string

    // Register aciGw
    route = "/api/v1/aciGws/{key}/"
    listRoute = "/api/v1/aciGws/"
    log.Infof("Registering %s", route)
    router.Path(listRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpListAciGws))
    router.Path(route).Methods("GET").HandlerFunc(makeHttpHandler(httpGetAciGw))
    router.Path(route).Methods("POST").HandlerFunc(makeHttpHandler(httpCreateAciGw))
    router.Path(route).Methods("PUT").HandlerFunc(makeHttpHandler(httpCreateAciGw))
    router.Path(route).Methods("DELETE").HandlerFunc(makeHttpHandler(httpDeleteAciGw))

    inspectRoute = "/api/v1/inspect/aciGws/{key}/"
    router.Path(inspectRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpInspectAciGw))

    // Register appProfile
    route = "/api/v1/appProfiles/{key}/"
    listRoute = "/api/v1/appProfiles/"
    log.Infof("Registering %s", route)
    router.Path(listRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpListAppProfiles))
    router.Path(route).Methods("GET").HandlerFunc(makeHttpHandler(httpGetAppProfile))
    router.Path(route).Methods("POST").HandlerFunc(makeHttpHandler(httpCreateAppProfile))
    router.Path(route).Methods("PUT").HandlerFunc(makeHttpHandler(httpCreateAppProfile))
    router.Path(route).Methods("DELETE").HandlerFunc(makeHttpHandler(httpDeleteAppProfile))

    inspectRoute = "/api/v1/inspect/appProfiles/{key}/"
    router.Path(inspectRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpInspectAppProfile))

    // Register Bgp
    route = "/api/v1/Bgps/{key}/"
    listRoute = "/api/v1/Bgps/"
    log.Infof("Registering %s", route)
    router.Path(listRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpListBgps))
    router.Path(route).Methods("GET").HandlerFunc(makeHttpHandler(httpGetBgp))
    router.Path(route).Methods("POST").HandlerFunc(makeHttpHandler(httpCreateBgp))
    router.Path(route).Methods("PUT").HandlerFunc(makeHttpHandler(httpCreateBgp))
    router.Path(route).Methods("DELETE").HandlerFunc(makeHttpHandler(httpDeleteBgp))

    inspectRoute = "/api/v1/inspect/Bgps/{key}/"
    router.Path(inspectRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpInspectBgp))

    inspectRoute = "/api/v1/inspect/endpoints/{key}/"
    router.Path(inspectRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpInspectEndpoint))

    // Register endpointGroup
    route = "/api/v1/endpointGroups/{key}/"
    listRoute = "/api/v1/endpointGroups/"
    log.Infof("Registering %s", route)
    router.Path(listRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpListEndpointGroups))
    router.Path(route).Methods("GET").HandlerFunc(makeHttpHandler(httpGetEndpointGroup))
    router.Path(route).Methods("POST").HandlerFunc(makeHttpHandler(httpCreateEndpointGroup))
    router.Path(route).Methods("PUT").HandlerFunc(makeHttpHandler(httpCreateEndpointGroup))
    router.Path(route).Methods("DELETE").HandlerFunc(makeHttpHandler(httpDeleteEndpointGroup))

    inspectRoute = "/api/v1/inspect/endpointGroups/{key}/"
    router.Path(inspectRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpInspectEndpointGroup))

    // Register extContractsGroup
    route = "/api/v1/extContractsGroups/{key}/"
    listRoute = "/api/v1/extContractsGroups/"
    log.Infof("Registering %s", route)
    router.Path(listRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpListExtContractsGroups))
    router.Path(route).Methods("GET").HandlerFunc(makeHttpHandler(httpGetExtContractsGroup))
    router.Path(route).Methods("POST").HandlerFunc(makeHttpHandler(httpCreateExtContractsGroup))
    router.Path(route).Methods("PUT").HandlerFunc(makeHttpHandler(httpCreateExtContractsGroup))
    router.Path(route).Methods("DELETE").HandlerFunc(makeHttpHandler(httpDeleteExtContractsGroup))

    inspectRoute = "/api/v1/inspect/extContractsGroups/{key}/"
    router.Path(inspectRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpInspectExtContractsGroup))

    // Register global
    route = "/api/v1/globals/{key}/"
    listRoute = "/api/v1/globals/"
    log.Infof("Registering %s", route)
    router.Path(listRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpListGlobals))
    router.Path(route).Methods("GET").HandlerFunc(makeHttpHandler(httpGetGlobal))
    router.Path(route).Methods("POST").HandlerFunc(makeHttpHandler(httpCreateGlobal))
    router.Path(route).Methods("PUT").HandlerFunc(makeHttpHandler(httpCreateGlobal))
    router.Path(route).Methods("DELETE").HandlerFunc(makeHttpHandler(httpDeleteGlobal))

    inspectRoute = "/api/v1/inspect/globals/{key}/"
    router.Path(inspectRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpInspectGlobal))

    // 做网络带宽限制
    // Register netprofile
    route = "/api/v1/netprofiles/{key}/"
    listRoute = "/api/v1/netprofiles/"
    log.Infof("Registering %s", route)
    router.Path(listRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpListNetprofiles))
    router.Path(route).Methods("GET").HandlerFunc(makeHttpHandler(httpGetNetprofile))
    router.Path(route).Methods("POST").HandlerFunc(makeHttpHandler(httpCreateNetprofile))
    router.Path(route).Methods("PUT").HandlerFunc(makeHttpHandler(httpCreateNetprofile))
    router.Path(route).Methods("DELETE").HandlerFunc(makeHttpHandler(httpDeleteNetprofile))

    inspectRoute = "/api/v1/inspect/netprofiles/{key}/"
    router.Path(inspectRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpInspectNetprofile))

    // Register network
    route = "/api/v1/networks/{key}/"
    listRoute = "/api/v1/networks/"
    log.Infof("Registering %s", route)
    router.Path(listRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpListNetworks))
    router.Path(route).Methods("GET").HandlerFunc(makeHttpHandler(httpGetNetwork))
    router.Path(route).Methods("POST").HandlerFunc(makeHttpHandler(httpCreateNetwork))
    router.Path(route).Methods("PUT").HandlerFunc(makeHttpHandler(httpCreateNetwork))
    router.Path(route).Methods("DELETE").HandlerFunc(makeHttpHandler(httpDeleteNetwork))

    inspectRoute = "/api/v1/inspect/networks/{key}/"
    router.Path(inspectRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpInspectNetwork))

    // 访问控制
    // Register policy
    route = "/api/v1/policys/{key}/"
    listRoute = "/api/v1/policys/"
    log.Infof("Registering %s", route)
    router.Path(listRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpListPolicys))
    router.Path(route).Methods("GET").HandlerFunc(makeHttpHandler(httpGetPolicy))
    router.Path(route).Methods("POST").HandlerFunc(makeHttpHandler(httpCreatePolicy))
    router.Path(route).Methods("PUT").HandlerFunc(makeHttpHandler(httpCreatePolicy))
    router.Path(route).Methods("DELETE").HandlerFunc(makeHttpHandler(httpDeletePolicy))

    inspectRoute = "/api/v1/inspect/policys/{key}/"
    router.Path(inspectRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpInspectPolicy))

    // Register rule
    route = "/api/v1/rules/{key}/"
    listRoute = "/api/v1/rules/"
    log.Infof("Registering %s", route)
    router.Path(listRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpListRules))
    router.Path(route).Methods("GET").HandlerFunc(makeHttpHandler(httpGetRule))
    router.Path(route).Methods("POST").HandlerFunc(makeHttpHandler(httpCreateRule))
    router.Path(route).Methods("PUT").HandlerFunc(makeHttpHandler(httpCreateRule))
    router.Path(route).Methods("DELETE").HandlerFunc(makeHttpHandler(httpDeleteRule))

    inspectRoute = "/api/v1/inspect/rules/{key}/"
    router.Path(inspectRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpInspectRule))

    // Register serviceLB
    route = "/api/v1/serviceLBs/{key}/"
    listRoute = "/api/v1/serviceLBs/"
    log.Infof("Registering %s", route)
    router.Path(listRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpListServiceLBs))
    router.Path(route).Methods("GET").HandlerFunc(makeHttpHandler(httpGetServiceLB))
    router.Path(route).Methods("POST").HandlerFunc(makeHttpHandler(httpCreateServiceLB))
    router.Path(route).Methods("PUT").HandlerFunc(makeHttpHandler(httpCreateServiceLB))
    router.Path(route).Methods("DELETE").HandlerFunc(makeHttpHandler(httpDeleteServiceLB))

    inspectRoute = "/api/v1/inspect/serviceLBs/{key}/"
    router.Path(inspectRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpInspectServiceLB))

    // Register tenant
    route = "/api/v1/tenants/{key}/"
    listRoute = "/api/v1/tenants/"
    log.Infof("Registering %s", route)
    router.Path(listRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpListTenants))
    router.Path(route).Methods("GET").HandlerFunc(makeHttpHandler(httpGetTenant))
    router.Path(route).Methods("POST").HandlerFunc(makeHttpHandler(httpCreateTenant))
    router.Path(route).Methods("PUT").HandlerFunc(makeHttpHandler(httpCreateTenant))
    router.Path(route).Methods("DELETE").HandlerFunc(makeHttpHandler(httpDeleteTenant))

    inspectRoute = "/api/v1/inspect/tenants/{key}/"
    router.Path(inspectRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpInspectTenant))

    // Register volume
    route = "/api/v1/volumes/{key}/"
    listRoute = "/api/v1/volumes/"
    log.Infof("Registering %s", route)
    router.Path(listRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpListVolumes))
    router.Path(route).Methods("GET").HandlerFunc(makeHttpHandler(httpGetVolume))
    router.Path(route).Methods("POST").HandlerFunc(makeHttpHandler(httpCreateVolume))
    router.Path(route).Methods("PUT").HandlerFunc(makeHttpHandler(httpCreateVolume))
    router.Path(route).Methods("DELETE").HandlerFunc(makeHttpHandler(httpDeleteVolume))

    inspectRoute = "/api/v1/inspect/volumes/{key}/"
    router.Path(inspectRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpInspectVolume))

    // Register volumeProfile
    route = "/api/v1/volumeProfiles/{key}/"
    listRoute = "/api/v1/volumeProfiles/"
    log.Infof("Registering %s", route)
    router.Path(listRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpListVolumeProfiles))
    router.Path(route).Methods("GET").HandlerFunc(makeHttpHandler(httpGetVolumeProfile))
    router.Path(route).Methods("POST").HandlerFunc(makeHttpHandler(httpCreateVolumeProfile))
    router.Path(route).Methods("PUT").HandlerFunc(makeHttpHandler(httpCreateVolumeProfile))
    router.Path(route).Methods("DELETE").HandlerFunc(makeHttpHandler(httpDeleteVolumeProfile))

    inspectRoute = "/api/v1/inspect/volumeProfiles/{key}/"
    router.Path(inspectRoute).Methods("GET").HandlerFunc(makeHttpHandler(httpInspectVolumeProfile))

}

### 恢复 mastercfg 中 ServiceLBDb 和 ProviderDb 缓存数据

**netmaster/daemon/daemon.go**

func (d *MasterDaemon) restoreCache() {

    //Restore ServiceLBDb and ProviderDb
    master.RestoreServiceProviderLBDb()

}

**netmaster/mastercfg/servicelbState.go**

//ServiceLBDb is map of all services
var ServiceLBDb = make(map[string]*ServiceLBInfo) //DB for all services keyed 

**netmaster/mastercfg/providerState.go**

//ProviderDb is map of providers for a service keyed by provider ip
var ProviderDb = make(map[string]*Provider)

**netmaster/master/servicelb.go**

//RestoreServiceProviderLBDb restores provider and servicelb db
func RestoreServiceProviderLBDb() {

    log.Infof("Restoring ProviderDb and ServiceDB cache")

    svcLBState := &mastercfg.CfgServiceLBState{}
    stateDriver, err := utils.GetStateDriver()
    if err != nil {
        log.Errorf("Error Restoring Service and ProviderDb Err:%s", err)
        return
    }
    svcLBState.StateDriver = stateDriver
    svcLBCfgs, err := svcLBState.ReadAll()

    if err == nil {
        mastercfg.SvcMutex.Lock()
        for _, svcLBCfg := range svcLBCfgs {
            svcLB := svcLBCfg.(*mastercfg.CfgServiceLBState)
            //mastercfg.ServiceLBDb = make(map[string]*mastercfg.ServiceLBInfo)
            serviceID := GetServiceID(svcLB.ServiceName, svcLB.Tenant)
            mastercfg.ServiceLBDb[serviceID] = &mastercfg.ServiceLBInfo{
                IPAddress:   svcLB.IPAddress,
                Tenant:      svcLB.Tenant,
                ServiceName: svcLB.ServiceName,
                Network:     svcLB.Network,
            }
            mastercfg.ServiceLBDb[serviceID].Ports = append(mastercfg.ServiceLBDb[serviceID].Ports, svcLB.Ports...)

            mastercfg.ServiceLBDb[serviceID].Selectors = make(map[string]string)
            mastercfg.ServiceLBDb[serviceID].Providers = make(map[string]*mastercfg.Provider)

            for k, v := range svcLB.Selectors {
                mastercfg.ServiceLBDb[serviceID].Selectors[k] = v
            }

            for providerID, providerInfo := range svcLB.Providers {
                mastercfg.ServiceLBDb[serviceID].Providers[providerID] = providerInfo
                providerDBId := providerInfo.ContainerID
                mastercfg.ProviderDb[providerDBId] = providerInfo
            }
        }
        mastercfg.SvcMutex.Unlock()
    }

    //Recover from endpoint state as well .
    epCfgState := mastercfg.CfgEndpointState{}
    epCfgState.StateDriver = stateDriver
    epCfgs, err := epCfgState.ReadAll()
    if err == nil {
        for _, epCfg := range epCfgs {
            ep := epCfg.(*mastercfg.CfgEndpointState)
            providerDBId := ep.ContainerID
            if ep.Labels != nil && mastercfg.ProviderDb[providerDBId] == nil {
                //Create provider info and store it in provider db
                providerInfo := &mastercfg.Provider{}
                providerInfo.ContainerID = ep.ContainerID
                providerInfo.Network = strings.Split(ep.NetID, ".")[0]
                providerInfo.Tenant = strings.Split(ep.NetID, ".")[1]
                providerInfo.Labels = make(map[string]string)
                providerInfo.IPAddress = ep.IPAddress

                for k, v := range ep.Labels {
                    providerInfo.Labels[k] = v
                }
                mastercfg.SvcMutex.Lock()
                mastercfg.ProviderDb[providerDBId] = providerInfo
                mastercfg.SvcMutex.Unlock()
            }
        }
    }
}

### 注册该 netmaster 节点

**netmaster/daemon/daemon.go**

func (d *MasterDaemon) registerService() {
    var err error

    ctrlURL := strings.Split(d.ControlURL, ":")
    masterIP := ctrlURL[0]
    masterPort, _ := strconv.Atoi(ctrlURL[1])

    // service info
    srvInfo := objdb.ServiceInfo{
        ServiceName: "netmaster",
        TTL:         10,
        HostAddr:    masterIP,
        Port:        masterPort,
        Role:        d.currState,
    }

    // Register the node with service registry
    err = d.objdbClient.RegisterService(srvInfo)
    if err != nil {
        log.Fatalf("Error registering service. Err: %v", err)
    }

    // service info
    srvInfo = objdb.ServiceInfo{
        ServiceName: "netmaster.rpc",
        TTL:         10,
        HostAddr:    masterIP,
        Port:        ofnet.OFNET_MASTER_PORT,
        Role:        d.currState,
    }

    // Register the node with service registry
    err = d.objdbClient.RegisterService(srvInfo)
    if err != nil {
        log.Fatalf("Error registering service. Err: %v", err)
    }

    log.Infof("Registered netmaster service with registry")
}

### 初始化 policy manager

**netmaster/mastercfg/policyState.go**

// InitPolicyMgr initializes the policy manager
func InitPolicyMgr(stateDriver core.StateDriver, ofm *ofnet.OfnetMaster) error {
    // save statestore and ofnet masters
    stateStore = stateDriver
    ofnetMaster = ofm

    // 恢复 endpoint group policies
    // restore all existing epg policies
    err := restoreEpgPolicies(stateDriver)
    if err != nil {
        log.Errorf("Error restoring EPG policies. ")
    }
    return nil
}

### 提供其他的 restful 接口

这些 restful 接口主要分为三类：

1. 分配 ip 和 contiv endpoint 接口：allocAddress、releaseAddress、createEndpoint、deleteEndpoint、updateEndpoint
2. 获取 netmaster 版本信息接口
3. service endpoint inspect 接口
4. ofnet inspect 接口
5. contiv 资源 network、endpointgroup、endpoint inspect 接口

**netmaster/daemon/daemon.go**

// registerRoutes registers HTTP route handlers
func (d *MasterDaemon) registerRoutes(router *mux.Router) {
    // Add REST routes
    s := router.Headers("Content-Type", "application/json").Methods("Post").Subrouter()

    s.HandleFunc("/plugin/allocAddress", utils.MakeHTTPHandler(master.AllocAddressHandler))
    s.HandleFunc("/plugin/releaseAddress", utils.MakeHTTPHandler(master.ReleaseAddressHandler))
    // CreateEndpointHandler 通过 state driver 新增 contiv endpoint
    s.HandleFunc("/plugin/createEndpoint", utils.MakeHTTPHandler(master.CreateEndpointHandler))
    // DeleteEndpointHandler 通过 state driver 删除 contiv endpoint
    s.HandleFunc("/plugin/deleteEndpoint", utils.MakeHTTPHandler(master.DeleteEndpointHandler))
    s.HandleFunc("/plugin/updateEndpoint", utils.MakeHTTPHandler(master.UpdateEndpointHandler))

    s = router.Methods("Get").Subrouter()

    // return netmaster version
    s.HandleFunc(fmt.Sprintf("/%s", master.GetVersionRESTEndpoint), getVersion)
    // Print info about the cluster
    s.HandleFunc(fmt.Sprintf("/%s", master.GetInfoRESTEndpoint), func(w http.ResponseWriter, r *http.Request) {
        info, err := d.getMasterInfo()
        if err != nil {
            log.Errorf("Error getting master state. Err: %v", err)
            http.Error(w, "Error getting master state", http.StatusInternalServerError)
            return
        }

        // convert to json
        resp, err := json.Marshal(info)
        if err != nil {
            http.Error(w,
                core.Errorf("marshaling json failed. Error: %s", err).Error(),
                http.StatusInternalServerError)
            return
        }
        w.Write(resp)
    })

    // services REST endpoints
    // FIXME: we need to remove once service inspect is added
    s.HandleFunc(fmt.Sprintf("/%s/%s", master.GetServiceRESTEndpoint, "{id}"),
        get(false, d.services))
    s.HandleFunc(fmt.Sprintf("/%s", master.GetServicesRESTEndpoint),
        get(true, d.services))

    // Debug REST endpoint for inspecting ofnet state
    s.HandleFunc("/debug/ofnet", func(w http.ResponseWriter, r *http.Request) {
        ofnetMasterState, err := d.ofnetMaster.InspectState()
        if err != nil {
            log.Errorf("Error fetching ofnet state. Err: %v", err)
            http.Error(w, "Error fetching ofnet state", http.StatusInternalServerError)
            return
        }
        w.Write(ofnetMasterState)
    })

    s = router.Methods("Delete").Subrouter()
    s.HandleFunc("/debug/epcleanup/tenant/{tenant}/{category}/{id}", func(w http.ResponseWriter, r *http.Request) {
        errStr := ""
        var epCfgs []core.State

        vars := mux.Vars(r)
        tenantName := vars["tenant"]
        category := vars["category"]
        id := vars["id"]

        // Get the state driver
        stateDriver, err := utils.GetStateDriver()
        if err != nil {
            log.Errorf("error getting state drive. Error: %+v", err)
            return
        }

        switch category {
        case "net":
            errStr = fmt.Sprintf("Received request to cleanup Network with ID: %s", id)
            nwKey := mastercfg.GetNwCfgKey(id, tenantName)
            nwCfg := &mastercfg.CfgNetworkState{}
            nwCfg.StateDriver = stateDriver
            err = nwCfg.Read(nwKey)
            if err != nil {
                log.Errorf("error reading network: %s. Error: %s", nwKey, err)
                return
            }

            if nwCfg.EpCount == 0 {
                return
            }
            readEp := &mastercfg.CfgEndpointState{}
            readEp.StateDriver = stateDriver
            epCfgs, err = readEp.ReadAll()
            if err != nil {
                log.Errorf("Could not read eps for network: %s. Err: %v", id, err)
                return
            }

            id = id + "." + tenantName
        case "group":
            errStr = fmt.Sprintf("Received request to cleanup EPG with ID: %s", id)

            epgKey := mastercfg.GetEndpointGroupKey(id, tenantName)
            epgCfg := &mastercfg.EndpointGroupState{}
            epgCfg.StateDriver = stateDriver
            err = epgCfg.Read(epgKey)
            if err != nil {
                log.Errorf("error reading EPG: %s. Error: %s", epgKey, err)
                return
            }

            if epgCfg.EpCount == 0 {
                return
            }
            readEp := &mastercfg.CfgEndpointState{}
            readEp.StateDriver = stateDriver
            epCfgs, err = readEp.ReadAll()
            if err != nil {
                log.Errorf("Could not read eps for group: %s. Err: %v", id, err)
                return
            }
        case "ep":
            errStr = fmt.Sprintf("Received request to cleanup Endpoint with ID: %s", id)
            readEp := &mastercfg.CfgEndpointState{}
            readEp.StateDriver = stateDriver
            epCfgs, err = readEp.ReadAll()
            if err != nil {
                log.Errorf("Could not read eps for group: %s. Err: %v", id, err)
                return
            }
        default:
            errStr = fmt.Sprintf("Unknown category error")
            return
        }
        err = d.ClearEndpoints(stateDriver, &epCfgs, id, category)
        if err != nil {
            log.Errorf("Error during ClearEndpoints. Err: %+v", err)
            return
        }
        http.Error(w, errStr, http.StatusOK)
        return
    })
}

#### contiv endpoint 创建

**netmaster/master/api.go**

// CreateEndpointHandler handles create endpoint requests
func CreateEndpointHandler(w http.ResponseWriter, r *http.Request, vars map[string]string) (interface{}, error) {
    var epReq CreateEndpointRequest

    // Gte the state driver
    stateDriver, err := utils.GetStateDriver()

    // find the network from network id
    netID := epReq.NetworkName + "." + epReq.TenantName
    nwCfg := &mastercfg.CfgNetworkState{}
    nwCfg.StateDriver = stateDriver
    err = nwCfg.Read(netID)

    // Create the endpoint
    epCfg, err := CreateEndpoint(stateDriver, nwCfg, &epReq)

    // build ep create response
    epResp := CreateEndpointResponse{
        EndpointConfig: *epCfg,
    }

    // return the response
    return epResp, nil
}

**netmaster/master/endpoint.go**

1. 为 endpoint 分配 ip
2. 通过 group 获取 EndpointGroupID
3. endpoint 写入 state driver

// CreateEndpoint creates an endpoint
func CreateEndpoint(stateDriver core.StateDriver, nwCfg *mastercfg.CfgNetworkState,
    epReq *CreateEndpointRequest) (*mastercfg.CfgEndpointState, error) {

    var epgCfg *mastercfg.EndpointGroupState
    ep := &epReq.ConfigEP
    epCfg := &mastercfg.CfgEndpointState{}
    epCfg.StateDriver = stateDriver
    epCfg.ID = getEpName(nwCfg.ID, ep)
    err := epCfg.Read(epCfg.ID)
    if err == nil {
        // TODO: check for diffs and possible updates
        return epCfg, nil
    }

    epCfg.NetID = nwCfg.ID
    epCfg.EndpointID = ep.Container
    epCfg.HomingHost = ep.Host
    // netplugin 通过 netmaster 创建 endpoint 的时候，epCfg.ServiceName 的值
    // 设置的是 pInfo.Group
    epCfg.ServiceName = ep.ServiceName
    epCfg.EPCommonName = epReq.EPCommonName

    if len(epCfg.ServiceName) > 0 {
        epgCfg = &mastercfg.EndpointGroupState{}
        epgCfg.StateDriver = stateDriver
        if err := epgCfg.Read(epCfg.ServiceName + ":" + nwCfg.Tenant); err != nil {
            log.Errorf("failed to read endpoint group %s, %v",
                epgCfg.GroupName+":"+epgCfg.TenantName, err)
            return nil, err
        }
    }

    // 为 endpoint 分配 ip
    // Allocate addresses
    err = allocSetEpAddress(ep, epCfg, nwCfg, epgCfg)
    if err != nil {
        log.Errorf("error allocating and/or reserving IP. Error: %s", err)
        return nil, err
    }

    // cleanup relies on var err being used for all error checking
    defer freeAddrOnErr(nwCfg, epgCfg, epCfg.IPAddress, &err)

    // 获取 EndpointGroupID
    // Set endpoint group
    // Skip for infra nw
    if nwCfg.NwType != "infra" {
        epCfg.EndpointGroupKey = mastercfg.GetEndpointGroupKey(epCfg.ServiceName, nwCfg.Tenant)
        epCfg.EndpointGroupID, err = mastercfg.GetEndpointGroupID(stateDriver, epCfg.ServiceName, nwCfg.Tenant)
        if err != nil {
            log.Errorf("Error getting endpoint group ID for %s.%s. Err: %v", epCfg.ServiceName, nwCfg.ID, err)
            return nil, err
        }

        if epCfg.EndpointGroupKey != "" {
            epgCfg := &mastercfg.EndpointGroupState{}
            epgCfg.StateDriver = stateDriver
            err = epgCfg.Read(epCfg.EndpointGroupKey)
            if err != nil {
                log.Errorf("Error reading Epg info for EP: %+v. Error: %v", ep, err)
                return nil, err
            }

            epgCfg.EpCount++

            err = epgCfg.Write()
            if err != nil {
                log.Errorf("Error saving epg state: %+v", epgCfg)
                return nil, err
            }
        }
    }

    err = nwCfg.IncrEpCount()
    if err != nil {
        log.Errorf("Error incrementing ep count. Err: %v", err)
        return nil, err
    }

    // endpoint 写入 state driver
    err = epCfg.Write()
    if err != nil {
        log.Errorf("error writing ep config. Error: %s", err)
        return nil, err
    }

    return epCfg, nil
}

##### 为 endpoint 分配 ip 和设置 mac 地址

**netmaster/master/endpoint.go**

func allocSetEpAddress(ep *intent.ConfigEP, epCfg *mastercfg.CfgEndpointState,
    nwCfg *mastercfg.CfgNetworkState, epgCfg *mastercfg.EndpointGroupState) (err error) {

    // 分配 ip 地址
    ipAddress, err := networkAllocAddress(nwCfg, epgCfg, ep.IPAddress, false)

    epCfg.IPAddress = ipAddress

    // 设置 mac 地址
    // Set mac address which is derived from IP address
    ipAddr := net.ParseIP(ipAddress)
    macAddr := fmt.Sprintf("02:02:%02x:%02x:%02x:%02x", ipAddr[12], ipAddr[13], ipAddr[14], ipAddr[15])

    epCfg.MacAddress = macAddr

    if nwCfg.IPv6Subnet != "" {
        var ipv6Address string
        ipv6Address, err = networkAllocAddress(nwCfg, nil, ep.IPv6Address, true)
        if err != nil {
            log.Errorf("Error allocating IP address. Err: %v", err)
            return
        }
        epCfg.IPv6Address = ipv6Address
    }

    return
}

**netmaster/master/network.go**

// Allocate an address from the network
func networkAllocAddress(nwCfg *mastercfg.CfgNetworkState, epgCfg *mastercfg.EndpointGroupState,
    reqAddr string, isIPv6 bool) (string, error) {
    var ipAddress string
    var ipAddrValue uint
    var found bool
    var err error
    var hostID string

    // alloc address
    if reqAddr == "" {
        if isIPv6 {
            // Get the next available IPv6 address
            hostID, err = netutils.GetNextIPv6HostID(nwCfg.IPv6LastHost, nwCfg.IPv6Subnet, nwCfg.IPv6SubnetLen, nwCfg.IPv6AllocMap)
            if err != nil {
                log.Errorf("create eps: error allocating ip. Error: %s", err)
                return "", err
            }
            ipAddress, err = netutils.GetSubnetIPv6(nwCfg.IPv6Subnet, nwCfg.IPv6SubnetLen, hostID)
            if err != nil {
                log.Errorf("create eps: error acquiring subnet ip. Error: %s", err)
                return "", err
            }
            nwCfg.IPv6LastHost = hostID
            netutils.ReserveIPv6HostID(hostID, &nwCfg.IPv6AllocMap)
        } else {
            if epgCfg != nil && len(epgCfg.IPPool) > 0 { // allocate from epg network
                log.Infof("allocating ip address from epg pool %s", epgCfg.IPPool)
                ipAddrValue, found = netutils.NextClear(epgCfg.EPGIPAllocMap, 0, nwCfg.SubnetLen)
                if !found {
                    log.Errorf("auto allocation failed - address exhaustion in pool %s",
                        epgCfg.IPPool)
                    err = core.Errorf("auto allocation failed - address exhaustion in pool %s",
                        epgCfg.IPPool)
                    return "", err
                }
                ipAddress, err = netutils.GetSubnetIP(nwCfg.SubnetIP, nwCfg.SubnetLen, 32, ipAddrValue)
                if err != nil {
                    log.Errorf("create eps: error acquiring subnet ip. Error: %s", err)
                    return "", err
                }
                epgCfg.EPGIPAllocMap.Set(ipAddrValue)
            } else {
                ipAddrValue, found = netutils.NextClear(nwCfg.IPAllocMap, 0, nwCfg.SubnetLen)
                if !found {
                    log.Errorf("auto allocation failed - address exhaustion in subnet %s/%d",
                        nwCfg.SubnetIP, nwCfg.SubnetLen)
                    err = core.Errorf("auto allocation failed - address exhaustion in subnet %s/%d",
                        nwCfg.SubnetIP, nwCfg.SubnetLen)
                    return "", err
                }
                ipAddress, err = netutils.GetSubnetIP(nwCfg.SubnetIP, nwCfg.SubnetLen, 32, ipAddrValue)
                if err != nil {
                    log.Errorf("create eps: error acquiring subnet ip. Error: %s", err)
                    return "", err
                }
                nwCfg.IPAllocMap.Set(ipAddrValue)
            }
        }

        // Docker, Mesos issue a Alloc Address first, followed by a CreateEndpoint
        // Kubernetes issues a create endpoint directly
        // since networkAllocAddress is called from both AllocAddressHandler and CreateEndpointHandler,
        // we need to make sure that the EpCount is incremented only when we are allocating
        // a new IP. In case of Docker, Mesos CreateEndPoint will already request a IP that
        // allocateAddress had allocated in the earlier call.
        nwCfg.EpAddrCount++

    } else if reqAddr != "" && nwCfg.SubnetIP != "" {
        if isIPv6 {
            hostID, err = netutils.GetIPv6HostID(nwCfg.IPv6Subnet, nwCfg.IPv6SubnetLen, reqAddr)
            if err != nil {
                log.Errorf("create eps: error getting host id from hostIP %s Subnet %s/%d. Error: %s",
                    reqAddr, nwCfg.IPv6Subnet, nwCfg.IPv6SubnetLen, err)
                return "", err
            }
            netutils.ReserveIPv6HostID(hostID, &nwCfg.IPv6AllocMap)
        } else {

            if epgCfg != nil && len(epgCfg.IPPool) > 0 { // allocate from epg network
                ipAddrValue, err = netutils.GetIPNumber(nwCfg.SubnetIP, nwCfg.SubnetLen, 32, reqAddr)
                if err != nil {
                    log.Errorf("create eps: error getting host id from hostIP %s pool %s. Error: %s",
                        reqAddr, epgCfg.IPPool, err)
                    return "", err
                }
                epgCfg.EPGIPAllocMap.Set(ipAddrValue)
            } else {
                ipAddrValue, err = netutils.GetIPNumber(nwCfg.SubnetIP, nwCfg.SubnetLen, 32, reqAddr)
                if err != nil {
                    log.Errorf("create eps: error getting host id from hostIP %s Subnet %s/%d. Error: %s",
                        reqAddr, nwCfg.SubnetIP, nwCfg.SubnetLen, err)
                    return "", err
                }
                nwCfg.IPAllocMap.Set(ipAddrValue)
            }
        }

        ipAddress = reqAddr
    }

    if epgCfg != nil && len(epgCfg.IPPool) > 0 {
        err = epgCfg.Write()
        if err != nil {
            log.Errorf("error writing epg config. Error: %s", err)
            return "", err
        }
    }

    err = nwCfg.Write()
    if err != nil {
        log.Errorf("error writing nw config. Error: %s", err)
        return "", err
    }

    return ipAddress, nil
}

#### contiv endpoint 删除

**netmaster/master/api.go**

// DeleteEndpointHandler handles delete endpoint requests
func DeleteEndpointHandler(w http.ResponseWriter, r *http.Request, vars map[string]string) (interface{}, error) {
    var epdelReq DeleteEndpointRequest

    // Get object from the request
    err := json.NewDecoder(r.Body).Decode(&epdelReq)
    if err != nil {
        log.Errorf("Error decoding AllocAddressHandler. Err %v", err)
        return nil, err
    }

    log.Infof("Received DeleteEndpointRequest: %+v", epdelReq)

    // Get the state driver
    stateDriver, err := utils.GetStateDriver()
    if err != nil {
        return nil, err
    }

    // Take a global lock for address release
    addrMutex.Lock()
    defer addrMutex.Unlock()

    // build the endpoint ID
    netID := epdelReq.NetworkName + "." + epdelReq.TenantName
    epID := getEpName(netID, &intent.ConfigEP{Container: epdelReq.EndpointID})

    // delete the endpoint
    epCfg, err := DeleteEndpointID(stateDriver, epID)
    if err != nil {
        log.Errorf("Error deleting endpoint: %v", epID)
        return nil, err
    }

    // build the response
    delResp := DeleteEndpointResponse{
        EndpointConfig: *epCfg,
    }

    // done. return resp
    return delResp, nil
}

**netmaster/master/endpoint.go**

1. 释放 ip
2. clear endpoint

// DeleteEndpointID deletes an endpoint by ID.
func DeleteEndpointID(stateDriver core.StateDriver, epID string) (*mastercfg.CfgEndpointState, error) {
    epCfg := &mastercfg.CfgEndpointState{}
    var epgCfg *mastercfg.EndpointGroupState

    epCfg.StateDriver = stateDriver
    err := epCfg.Read(epID)
    if err != nil {
        return nil, err
    }

    nwCfg := &mastercfg.CfgNetworkState{}
    nwCfg.StateDriver = stateDriver
    err = nwCfg.Read(epCfg.NetID)

    // Network may already be deleted if infra nw
    // If network present, free up nw resources
    if err == nil && epCfg.IPAddress != "" {
        if len(epCfg.ServiceName) > 0 {
            epgCfg = &mastercfg.EndpointGroupState{}
            epgCfg.StateDriver = stateDriver
            if err := epgCfg.Read(epCfg.ServiceName + ":" + nwCfg.Tenant); err != nil {
                log.Errorf("failed to read endpoint group %s, error %s",
                    epCfg.ServiceName+":"+epgCfg.TenantName, err)
                return nil, err
            }
        }

        err = networkReleaseAddress(nwCfg, epgCfg, epCfg.IPAddress)
        if err != nil {
            log.Errorf("Error releasing endpoint state for: %s. Err: %v", epCfg.IPAddress, err)
        }

        if epCfg.EndpointGroupKey != "" {
            epgCfg := &mastercfg.EndpointGroupState{}
            epgCfg.StateDriver = stateDriver
            err = epgCfg.Read(epCfg.EndpointGroupKey)
            if err != nil {
                log.Errorf("Error reading EPG for endpoint: %+v", epCfg)
            }

            epgCfg.EpCount--

            // write updated epg state
            err = epgCfg.Write()
            if err != nil {
                log.Errorf("error writing epg config. Error: %s", err)
            }
        }

        // decrement ep count
        nwCfg.EpCount--

        // write modified nw state
        err = nwCfg.Write()
        if err != nil {
            log.Errorf("error writing nw config. Error: %s", err)
        }
    }

    // Even if network not present (already deleted), cleanup ep cfg
    err = epCfg.Clear()
    if err != nil {
        log.Errorf("error writing ep config. Error: %s", err)
        return nil, err
    }

    return epCfg, err
}

##### 释放 endpoint ip

**netmaster/master/network.go**

// networkReleaseAddress release the ip address
func networkReleaseAddress(nwCfg *mastercfg.CfgNetworkState, epgCfg *mastercfg.EndpointGroupState, ipAddress string) error {
    isIPv6 := netutils.IsIPv6(ipAddress)
    if isIPv6 {
        hostID, err := netutils.GetIPv6HostID(nwCfg.SubnetIP, nwCfg.SubnetLen, ipAddress)
        if err != nil {
            log.Errorf("error getting host id from hostIP %s Subnet %s/%d. Error: %s",
                ipAddress, nwCfg.SubnetIP, nwCfg.SubnetLen, err)
            return err
        }
        // networkReleaseAddress is called from multiple places
        // Make sure we decrement the EpCount only if the IPAddress
        // was not already freed earlier
        if _, found := nwCfg.IPv6AllocMap[hostID]; found {
            nwCfg.EpAddrCount--
        }
        delete(nwCfg.IPv6AllocMap, hostID)
    } else {
        if epgCfg != nil && len(epgCfg.IPPool) > 0 {
            log.Infof("releasing epg ip: %s", ipAddress)
            ipAddrValue, err := netutils.GetIPNumber(nwCfg.SubnetIP, nwCfg.SubnetLen, 32, ipAddress)
            if err != nil {
                log.Errorf("error getting host id from hostIP %s pool %s. Error: %s",
                    ipAddress, epgCfg.IPPool, err)
                return err
            }
            // networkReleaseAddress is called from multiple places
            // Make sure we decrement the EpCount only if the IPAddress
            // was not already freed earlier
            if epgCfg.EPGIPAllocMap.Test(ipAddrValue) {
                nwCfg.EpAddrCount--
            }
            epgCfg.EPGIPAllocMap.Clear(ipAddrValue)
            if err := epgCfg.Write(); err != nil {
                log.Errorf("error writing epg config. Error: %s", err)
                return err
            }

        } else {
            ipAddrValue, err := netutils.GetIPNumber(nwCfg.SubnetIP, nwCfg.SubnetLen, 32, ipAddress)
            if err != nil {
                log.Errorf("error getting host id from hostIP %s Subnet %s/%d. Error: %s",
                    ipAddress, nwCfg.SubnetIP, nwCfg.SubnetLen, err)
                return err
            }
            // networkReleaseAddress is called from multiple places
            // Make sure we decrement the EpCount only if the IPAddress
            // was not already freed earlier
            if nwCfg.IPAllocMap.Test(ipAddrValue) {
                nwCfg.EpAddrCount--
            }
            nwCfg.IPAllocMap.Clear(ipAddrValue)
            log.Infof("Releasing IP Address: %v"+
                "from networkId:%+v", ipAddrValue,
                nwCfg.NetworkName)
        }
    }
    err := nwCfg.Write()
    if err != nil {
        log.Errorf("error writing nw config. Error: %s", err)
        return err
    }

    return nil
}

## endpointgroup 创建

```
NAME:
   netctl group create - Create an endpoint group

USAGE:
   netctl group create [command options] [network] [group]

OPTIONS:
   --tenant, -t "default"                               Name of the tenant
   --policy, -p [--policy option --policy option]                   Policy
   --networkprofile, -n                                 network profile
   --external-contract, -e [--external-contract option --external-contract option]  External contract
   --ip-pool, -r                                    IP Address range, example 10.36.0.1-10.36.0.10
   --epg-tag, --tag                                     Configured Group Tag
```

**contivModel/contivModel.go**

type EndpointGroup struct {
    // every object has a key
    Key string `json:"key,omitempty"`

    CfgdTag          string   `json:"cfgdTag,omitempty"` // Configured Group Tag
    ExtContractsGrps []string `json:"extContractsGrps,omitempty"`
    GroupName        string   `json:"groupName,omitempty"`   // Group name
    IpPool           string   `json:"ipPool,omitempty"`      // IP-pool
    NetProfile       string   `json:"netProfile,omitempty"`  // Network profile name
    NetworkName      string   `json:"networkName,omitempty"` // Network
    Policies         []string `json:"policies,omitempty"`
    TenantName       string   `json:"tenantName,omitempty"` // Tenant

    // add link-sets and links
    LinkSets EndpointGroupLinkSets `json:"link-sets,omitempty"`
    Links    EndpointGroupLinks    `json:"links,omitempty"`
}

// CREATE REST call
func httpCreateEndpointGroup(w http.ResponseWriter, r *http.Request, vars map[string]string) (interface{}, error) {
    log.Debugf("Received httpGetEndpointGroup: %+v", vars)

    var obj EndpointGroup
    key := vars["key"]

    // Get object from the request
    err := json.NewDecoder(r.Body).Decode(&obj)
    if err != nil {
        log.Errorf("Error decoding endpointGroup create request. Err %v", err)
        return nil, err
    }

    // set the key
    obj.Key = key

    // Create the object
    err = CreateEndpointGroup(&obj)
    if err != nil {
        log.Errorf("CreateEndpointGroup error for: %+v. Err: %v", obj, err)
        return nil, err
    }

    // Return the obj
    return obj, nil
}

// Create a endpointGroup object
func CreateEndpointGroup(obj *EndpointGroup) error {
    // Validate parameters
    err := ValidateEndpointGroup(obj)
    if err != nil {
        log.Errorf("ValidateEndpointGroup retruned error for: %+v. Err: %v", obj, err)
        return err
    }

    // Check if we handle this object
    if objCallbackHandler.EndpointGroupCb == nil {
        log.Errorf("No callback registered for endpointGroup object")
        return errors.New("Invalid object type")
    }

    saveObj := obj

    collections.endpointGroupMutex.Lock()
    key := collections.endpointGroups[obj.Key]
    collections.endpointGroupMutex.Unlock()

    // Check if object already exists
    if key != nil {
        // Perform Update callback
        err = objCallbackHandler.EndpointGroupCb.EndpointGroupUpdate(collections.endpointGroups[obj.Key], obj)
        if err != nil {
            log.Errorf("EndpointGroupUpdate retruned error for: %+v. Err: %v", obj, err)
            return err
        }

        // save the original object after update
        collections.endpointGroupMutex.Lock()
        saveObj = collections.endpointGroups[obj.Key]
        collections.endpointGroupMutex.Unlock()
    } else {
        // save it in cache
        collections.endpointGroupMutex.Lock()
        collections.endpointGroups[obj.Key] = obj
        collections.endpointGroupMutex.Unlock()

        // Perform Create callback
        err = objCallbackHandler.EndpointGroupCb.EndpointGroupCreate(obj)
        if err != nil {
            log.Errorf("EndpointGroupCreate retruned error for: %+v. Err: %v", obj, err)
            collections.endpointGroupMutex.Lock()
            delete(collections.endpointGroups, obj.Key)
            collections.endpointGroupMutex.Unlock()
            return err
        }
    }

    // Write it to modeldb
    collections.endpointGroupMutex.Lock()
    err = saveObj.Write()
    collections.endpointGroupMutex.Unlock()
    if err != nil {
        log.Errorf("Error saving endpointGroup %s to db. Err: %v", saveObj.Key, err)
        return err
    }

    return nil
}

**netmaster/objApi/apiController.go**

// EndpointGroupCreate creates Endpoint Group
func (ac *APIController) EndpointGroupCreate(endpointGroup *contivModel.EndpointGroup) error {
    log.Infof("Received EndpointGroupCreate: %+v", endpointGroup)

    // Find the tenant
    tenant := contivModel.FindTenant(endpointGroup.TenantName)

    // Find the network
    nwObjKey := endpointGroup.TenantName + ":" + endpointGroup.NetworkName
    network := contivModel.FindNetwork(nwObjKey)

    // create the endpoint group state
    err := master.CreateEndpointGroup(endpointGroup.TenantName, endpointGroup.NetworkName,
        endpointGroup.GroupName, endpointGroup.IpPool, endpointGroup.CfgdTag)

    // for each policy create an epg policy Instance
    for _, policyName := range endpointGroup.Policies {
        policyKey := GetpolicyKey(endpointGroup.TenantName, policyName)
        // find the policy
        policy := contivModel.FindPolicy(policyKey)

        // attach policy to epg
        err = master.PolicyAttach(endpointGroup, policy)

        // establish Links
        modeldb.AddLinkSet(&policy.LinkSets.EndpointGroups, endpointGroup)
        modeldb.AddLinkSet(&endpointGroup.LinkSets.Policies, policy)

        // Write the policy
        err = policy.Write()
    }

    // If endpoint group is to be attached to any netprofile, then attach the netprofile and create links and linksets.
    if endpointGroup.NetProfile != "" {
        profileKey := GetNetprofileKey(endpointGroup.TenantName, endpointGroup.NetProfile)
        netprofile := contivModel.FindNetprofile(profileKey)

        // attach NetProfile to epg
        err = master.UpdateEndpointGroup(netprofile.Bandwidth, endpointGroup.GroupName, endpointGroup.TenantName, netprofile.DSCP, netprofile.Burst)

        //establish links (epg - netprofile)
        modeldb.AddLink(&endpointGroup.Links.NetProfile, netprofile)
        //establish linksets (Netprofile - epg)
        modeldb.AddLinkSet(&netprofile.LinkSets.EndpointGroups, endpointGroup)

        //Write the attached Netprofile to modeldb
        err = netprofile.Write()
        if err != nil {
            endpointGroupCleanup(endpointGroup)
            return err
        }
    }

    // Setup external contracts this EPG might have.
    err = setupExternalContracts(endpointGroup, endpointGroup.ExtContractsGrps)

    // Setup links
    modeldb.AddLink(&endpointGroup.Links.Network, network)
    modeldb.AddLink(&endpointGroup.Links.Tenant, tenant)
    modeldb.AddLinkSet(&network.LinkSets.EndpointGroups, endpointGroup)
    modeldb.AddLinkSet(&tenant.LinkSets.EndpointGroups, endpointGroup)

    // Save the tenant and network since we added the links
    err = network.Write()

    err = tenant.Write()

    return nil
}

**netmaster/master/endpointGroup.go**

// CreateEndpointGroup handles creation of endpoint group
func CreateEndpointGroup(tenantName, networkName, groupName, ipPool, cfgdTag string) error {
    var epgID int

    // Get the state driver
    stateDriver, err := utils.GetStateDriver()

    // Read global config
    gstate.GlobalMutex.Lock()
    defer gstate.GlobalMutex.Unlock()
    gCfg := gstate.Cfg{}
    gCfg.StateDriver = stateDriver
    err = gCfg.Read(tenantName)
    if err != nil {
        log.Errorf("error reading tenant cfg state. Error: %s", err)
        return err
    }

    // read the network config
    networkID := networkName + "." + tenantName
    nwCfg := &mastercfg.CfgNetworkState{}
    nwCfg.StateDriver = stateDriver
    err = nwCfg.Read(networkID)
    if err != nil {
        log.Errorf("Could not find network %s. Err: %v", networkID, err)
        return err
    }

    // check epg range is with in network
    if len(ipPool) > 0 {
        if netutils.IsIPv6(ipPool) == true {
            return fmt.Errorf("ipv6 address pool is not supported for Endpoint Groups")
        }

        if err = netutils.ValidateNetworkRangeParams(ipPool, nwCfg.SubnetLen); err != nil {
            return fmt.Errorf("invalid ip-pool %s", ipPool)
        }

        addrRangeList := strings.Split(ipPool, "-")
        if _, err := netutils.GetIPNumber(nwCfg.SubnetIP, nwCfg.SubnetLen, 32, addrRangeList[0]); err != nil {
            return fmt.Errorf("bad ip-pool %s, EPG ip-pool must be a subset of network %s/%d", ipPool, nwCfg.SubnetIP,
                nwCfg.SubnetLen)
        }
        if _, err := netutils.GetIPNumber(nwCfg.SubnetIP, nwCfg.SubnetLen, 32, addrRangeList[1]); err != nil {
            return fmt.Errorf("bad ip-pool %s, EPG ip-pool must be a subset of network %s/%d", ipPool, nwCfg.SubnetIP,
                nwCfg.SubnetLen)
        }

        if err := netutils.TestIPAddrRange(&nwCfg.IPAllocMap, ipPool, nwCfg.SubnetIP,
            nwCfg.SubnetLen); err != nil {
            return err
        }
    }

    // if there is no label given generate one for the epg
    epgTag := cfgdTag
    if epgTag == "" {
        epgTag = groupName + "." + tenantName
    }

    // assign unique endpoint group ids
    // FIXME: This is a hack. need to add a epgID resource
    for i := 0; i < maxEpgID; i++ {
        epgID = globalEpgID
        globalEpgID = globalEpgID + 1
        if globalEpgID > maxEpgID {
            globalEpgID = 1
        }
        epgCfg := &mastercfg.EndpointGroupState{}
        epgCfg.StateDriver = stateDriver
        err = epgCfg.Read(strconv.Itoa(epgID))
        if err != nil {
            break
        }
    }

    // Create epGroup state
    epgCfg := &mastercfg.EndpointGroupState{
        GroupName:       groupName,
        TenantName:      tenantName,
        NetworkName:     networkName,
        IPPool:          ipPool,
        EndpointGroupID: epgID,
        PktTagType:      nwCfg.PktTagType,
        PktTag:          nwCfg.PktTag,
        ExtPktTag:       nwCfg.ExtPktTag,
        GroupTag:        epgTag,
    }

    epgCfg.StateDriver = stateDriver
    epgCfg.ID = mastercfg.GetEndpointGroupKey(groupName, tenantName)
    log.Debugf("##Create EpGroup %v network %v tagtype %v", groupName, networkName, nwCfg.PktTagType)

    if len(ipPool) > 0 {
        // mark range as used
        netutils.SetIPAddrRange(&nwCfg.IPAllocMap, ipPool, nwCfg.SubnetIP, nwCfg.SubnetLen)

        if err := nwCfg.Write(); err != nil {
            return fmt.Errorf("updating epg ipaddress in network failed: %s", err)
        }
        netutils.InitSubnetBitset(&epgCfg.EPGIPAllocMap, nwCfg.SubnetLen)
        netutils.SetBitsOutsideRange(&epgCfg.EPGIPAllocMap, ipPool, nwCfg.SubnetLen)
    }
    return epgCfg.Write()
}

## endpointgroup 删除

**contivModel/contivModel.go**

// DELETE rest call
func httpDeleteEndpointGroup(w http.ResponseWriter, r *http.Request, vars map[string]string) (interface{}, error) {
    log.Debugf("Received httpDeleteEndpointGroup: %+v", vars)

    key := vars["key"]

    // Delete the object
    err := DeleteEndpointGroup(key)
    if err != nil {
        log.Errorf("DeleteEndpointGroup error for: %s. Err: %v", key, err)
        return nil, err
    }

    // Return the obj
    return key, nil
}

// Delete a endpointGroup object
func DeleteEndpointGroup(key string) error {
    collections.endpointGroupMutex.Lock()
    obj := collections.endpointGroups[key]
    collections.endpointGroupMutex.Unlock()

    // Perform callback
    err := objCallbackHandler.EndpointGroupCb.EndpointGroupDelete(obj)

    // delete it from modeldb
    collections.endpointGroupMutex.Lock()
    err = obj.Delete()
    collections.endpointGroupMutex.Unlock()

    // delete it from cache
    collections.endpointGroupMutex.Lock()
    delete(collections.endpointGroups, key)
    collections.endpointGroupMutex.Unlock()

    return nil
}

**netmaster/objApi/apiController.go**

// EndpointGroupDelete deletes end point group
func (ac *APIController) EndpointGroupDelete(endpointGroup *contivModel.EndpointGroup) error {
    log.Infof("Received EndpointGroupDelete: %+v", endpointGroup)

    // if this is associated with an app profile, reject the delete
    if endpointGroup.Links.AppProfile.ObjKey != "" {
        return core.Errorf("Cannot delete %s, associated to appProfile %s",
            endpointGroup.GroupName, endpointGroup.Links.AppProfile.ObjKey)
    }

    // get the netprofile structure by finding the netprofile
    profileKey := GetNetprofileKey(endpointGroup.TenantName, endpointGroup.NetProfile)
    netprofile := contivModel.FindNetprofile(profileKey)

    if netprofile != nil {
        // Remove linksets from netprofile.
        modeldb.RemoveLinkSet(&netprofile.LinkSets.EndpointGroups, endpointGroup)
    }

    err := endpointGroupCleanup(endpointGroup)
    if err != nil {
        log.Errorf("EPG cleanup failed: %+v", err)
    }

    return err

}

// Cleans up state off endpointGroup and related objects.
func endpointGroupCleanup(endpointGroup *contivModel.EndpointGroup) error {
    // delete the endpoint group state
    err := master.DeleteEndpointGroup(endpointGroup.TenantName, endpointGroup.GroupName)

    // Detach the endpoint group from the Policies
    for _, policyName := range endpointGroup.Policies {
        policyKey := GetpolicyKey(endpointGroup.TenantName, policyName)

        // find the policy
        policy := contivModel.FindPolicy(policyKey)
        if policy == nil {
            log.Errorf("Could not find policy %s", policyName)
            continue
        }

        // detach policy to epg
        err := master.PolicyDetach(endpointGroup, policy)
        if err != nil && err != master.EpgPolicyExists {
            log.Errorf("Error detaching policy %s from epg %s", policyName, endpointGroup.Key)
        }

        // Remove links
        modeldb.RemoveLinkSet(&policy.LinkSets.EndpointGroups, endpointGroup)
        modeldb.RemoveLinkSet(&endpointGroup.LinkSets.Policies, policy)
        policy.Write()
    }

    // Cleanup any external contracts
    err = cleanupExternalContracts(endpointGroup)
    if err != nil {
        log.Errorf("Error cleaning up external contracts for epg %s", endpointGroup.Key)
    }

    // Remove the endpoint group from network and tenant link sets.
    nwObjKey := endpointGroup.TenantName + ":" + endpointGroup.NetworkName
    network := contivModel.FindNetwork(nwObjKey)
    if network != nil {
        modeldb.RemoveLinkSet(&network.LinkSets.EndpointGroups, endpointGroup)
        network.Write()
    }
    tenant := contivModel.FindTenant(endpointGroup.TenantName)
    if tenant != nil {
        modeldb.RemoveLinkSet(&tenant.LinkSets.EndpointGroups, endpointGroup)
        tenant.Write()
    }

    return nil
}

# References

1. https://github.com/contiv/ofnet
2. https://www.opennetworking.org/wp-content/uploads/2013/04/openflow-spec-v1.3.1.pdf
3. https://www.cnblogs.com/CasonChan/p/4626099.html
4. https://www.cnblogs.com/CasonChan/p/4620652.html
5. https://zhuanlan.zhihu.com/p/23135096
