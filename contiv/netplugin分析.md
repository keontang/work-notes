# netplugin 框架代码分析

netplugin 主要做如下事情：

1. 初始化 Node 上 netplugin 实例
2. List & Watch contiv 资源：`Network`、`BGP`、`Endpoint`、`EndpointGroup`、`ServiceLB`、`ServiceProvider`、`PolicyRule`、`GlobalConfig`，并根据这些资源的变化更新 netplugin 实例所在 Node 的网络状态（Iptable、Ovs Switch 等信息）
3. 为 cni plugin 提供将 pod 添加到 contiv 网络和将 pod 从 contiv 网络中删除的 restful api
4. List & Watch K8S Service 和 Endpoint，并根据这些资源的变化更新 netplugin 实例所在 Node 的网络状态（Iptable、Ovs Switch 等信息）

特别的，contiv 的 `ServiceLB`、`ServiceProvider` 用于非 K8S 模式中，因为 K8S 有自己的 Service 和 Endpoint 资源。

## netplugin 参数分析

```
NAME:
   netplugin - Contiv netplugin service

USAGE:
   netplugin [global options] command [command options] [arguments...]

VERSION:

Version: <netplugin-version>
GitCommit: <netplugin-commit-sha>
BuildTime: <netplugin-build-time>


COMMANDS:
     help, h  Shows a list of commands or help for one command

GLOBAL OPTIONS:
   --consul-endpoints value, --consul value                 a comma-delimited list of netplugin consul endpoints [$CONTIV_NETPLUGIN_CONSUL_ENDPOINTS]
   --ctrl-ip value                                          set netplugin control ip for control plane communication (default: <host-ip-from-local-resolver>) [$CONTIV_NETPLUGIN_CONTROL_IP]
   --etcd-endpoints value, --etcd value                     a comma-delimited list of netplugin etcd endpoints (default: http://127.0.0.1:2379) [$CONTIV_NETPLUGIN_ETCD_ENDPOINTS]
   --fwdmode value, --forward-mode value                    set netplugin forwarding network mode, options: [bridge, routing] [$CONTIV_NETPLUGIN_FORWARD_MODE]
   --host value, --host-label value                         set netplugin host to identify itself (default: <host-name-reported-by-the-kernel>) [$CONTIV_NETPLUGIN_HOST]
   --log-level value                                        set netplugin log level, options: [DEBUG, INFO, WARN, ERROR] (default: "INFO") [$CONTIV_NETPLUGIN_LOG_LEVEL]
   --mode value, --plugin-mode value, --cluster-mode value  set netplugin mode, options: [docker, kubernetes, swarm-mode] [$CONTIV_NETPLUGIN_MODE]
   --netmode value, --network-mode value                    set netplugin network mode, options: [vlan, vxlan] [$CONTIV_NETPLUGIN_NET_MODE]
   --syslog-url value                                       set netplugin syslog url in format protocol://ip:port (default: "udp://127.0.0.1:514") [$CONTIV_NETPLUGIN_SYSLOG_URL]
   --use-json-log, --json-log                               set netplugin log format to json if this flag is provided [$CONTIV_NETPLUGIN_USE_JSON_LOG]
   --use-syslog, --syslog                                   set netplugin send log to syslog if this flag is provided [$CONTIV_NETPLUGIN_USE_SYSLOG]
   --vlan-uplinks value, --vlan-if value                    a comma-delimited list of netplugin uplink interfaces [$CONTIV_NETPLUGIN_VLAN_UPLINKS]
   --vtep-ip value                                          set netplugin vtep ip for vxlan communication (default: <host-ip-from-local-resolver>) [$CONTIV_NETPLUGIN_VTEP_IP]
   --vxlan-port value                                       set netplugin VXLAN port (default: 4789) [$CONTIV_NETPLUGIN_VXLAN_PORT]
   --help, -h                                               show help
   --version, -v                                            print the version
```

## 相关数据结构

**netmaster/mastercfg/networkstate.go**

// CfgNetworkState implements the State interface for a network implemented using
// vlans with ovs. The state is stored as Json objects.
type CfgNetworkState struct {
    core.CommonState
    Tenant        string          `json:"tenant"`
    NetworkName   string          `json:"networkName"`
    NwType        string          `json:"nwType"`
    PktTagType    string          `json:"pktTagType"`
    PktTag        int             `json:"pktTag"`
    ExtPktTag     int             `json:"extPktTag"`
    SubnetIP      string          `json:"subnetIP"`
    SubnetLen     uint            `json:"subnetLen"`
    Gateway       string          `json:"gateway"`
    IPAddrRange   string          `json:"ipAddrRange"`
    EpAddrCount   int             `json:"epAddrCount"`
    EpCount       int             `json:"epCount"`
    IPAllocMap    bitset.BitSet   `json:"ipAllocMap"`
    IPv6Subnet    string          `json:"ipv6SubnetIP"`
    IPv6SubnetLen uint            `json:"ipv6SubnetLen"`
    IPv6Gateway   string          `json:"ipv6Gateway"`
    IPv6AllocMap  map[string]bool `json:"ipv6AllocMap"`
    IPv6LastHost  string          `json:"ipv6LastHost"`
    NetworkTag    string          `json:"networkTag"`
}

**netmaster/mastercfg/endpointstate.go**

// contiv endpoint 跟 k8s pod 是一一对应关系
// CfgEndpointState implements the State interface for an endpoint implemented using
// vlans with ovs. The state is stored as Json objects.
type CfgEndpointState struct {
    core.CommonState
    NetID            string            `json:"netID"`
    EndpointID       string            `json:"endpointID"`
    ServiceName      string            `json:"serviceName"`
    EndpointGroupID  int               `json:"endpointGroupId"`
    EndpointGroupKey string            `json:"endpointGroupKey"`
    IPAddress        string            `json:"ipAddress"`
    IPv6Address      string            `json:"ipv6Address"`
    MacAddress       string            `json:"macAddress"`
    HomingHost       string            `json:"homingHost"`
    IntfName         string            `json:"intfName"`
    VtepIP           string            `json:"vtepIP"`
    Labels           map[string]string `json:"labels"`
    ContainerID      string            `json:"containerId"`
    EPCommonName     string            `json:"epCommonName"`
}

**netmaster/mastercfg/bgpState.go**

// CfgBgpState is the router Bgp configuration for the host
type CfgBgpState struct {
    core.CommonState
    Hostname   string `json:"hostname"`
    RouterIP   string `json:"router-ip"`
    As         string `json:"as"`
    NeighborAs string `json:"neighbor-as"`
    Neighbor   string `json:"neighbor"`
}

**netmaster/mastercfg/providerState.go**

//SvcProvider holds service information
type SvcProvider struct {
    core.CommonState
    ServiceName string
    Providers   []string
}

//Provider has providers info
type Provider struct {
    IPAddress   string            // provider IP
    ContainerID string            // container id
    Labels      map[string]string // lables
    Tenant      string
    Network     string
    Services    []string
    Container   string //container endpoint id
    EpIDKey     string
}

**netmaster/mastercfg/servicelbState.go**

// CfgServiceLBState is the service object configuration
type CfgServiceLBState struct {
    core.CommonState
    ServiceName string               `json:"servicename"`
    Tenant      string               `json:"tenantname"`
    Network     string               `json:"subnet"`
    Ports       []string             `json:"ports"`
    Selectors   map[string]string    `json:"selectors"`
    IPAddress   string               `json:"ipaddress"`
    Providers   map[string]*Provider `json:"providers"`
}

//ServiceLBInfo holds service information
type ServiceLBInfo struct {
    ServiceName string               //Service name
    IPAddress   string               //Service IP
    Tenant      string               //Tenant name of the service
    Network     string               // service network
    Ports       []string             //Service_port:Provider_port:protocol
    Selectors   map[string]string    // selector labels associated with a service
    Providers   map[string]*Provider //map of providers for a service keyed by provider ip
}

## 程序入口

**netplugin/netd.go**

func startNetPlugin(pluginConfig *plugin.Config) {
    // Node 上创建 netplugin 实例
    // Create a new agent
    ag := agent.NewAgent(pluginConfig)

    // 从 state store 获取该 Node 的当前状态，更新该 Node 的网络信息，比如
    // ovs 流表信息，iptables 信息等
    // Process all current state
    ag.ProcessCurrentState()

    // 1. 将 Netplugin 实例 service 添加到 cluster
    // 2. 侦听 cluster Netplugin 实例和 Netmaster 实例变化信息，并更新该 
    //   Netplugin 实例所在 Node 的网络信息
    // 3. 启动 Netplugin 实例 restful 服务，提供暴露Netplugin 实例信息和调试接口
    // post initialization processing
    ag.PostInit()

    // Netplugin 实例进入正式工作状态
    // netplugin 实例 wait 等待处理各种 event
    // handle events
    if err := ag.HandleEvents(); err != nil {
        logrus.Errorf("Netplugin exiting due to error: %v", err)
        os.Exit(1)
    }
}

## NewAgent 负责在 Node 上创建 netplugin 实例

**netplugin/agent/agent.go**

// NewAgent creates a new netplugin agent
func NewAgent(pluginConfig *plugin.Config) *Agent {
    // 创建基于 etcd/consul 存储的 client
    // init cluster state
    err := cluster.Init(pluginConfig.Drivers.State, []string{opts.DbURL})

    // 1. 初始化基于 etcd/consul 存储的状态驱动
    // 2. 初始化基于 ovs/vpp 的网络驱动
    // Init the driver plugins..
    err = netPlugin.Init(*pluginConfig)

    // 这里只关注 kubernetes 模式
    // Initialize appropriate plugin
    switch opts.PluginMode {
    case core.Kubernetes:
        // 1. 创建 k8s client
        // 2. 启动 restful server 为 cni plugin 提供服务
        //   2.1 提供将 pod 添加到 contiv 网络的 api
        //   2.2 提供将 pod 从 contiv 网络删除的 api
        k8splugin.InitCNIServer(netPlugin)
    }

    // create a new agent
    agent := &Agent{
        netPlugin:    netPlugin,
        pluginConfig: pluginConfig,
    }

    return agent
}

### 创建基于 etcd/consul 存储的 client

**netplugin/cluster/cluster.go**

// This file implements netplugin <-> netmaster clustering

// Init initializes the cluster module
func Init(storeDriver string, storeURLs []string) error {
    var err error

    // objdb 通过封装 etcd or consul 提供 Object store API
    // Create an objdb client
    ObjdbClient, err = objdb.InitClient(storeDriver, storeURLs)

    return err
}


### 初始化 netplugin 依赖的驱动

**netplugin/plugin/netplugin.go**

// Drivers has driver config
type Drivers struct {
    Network  string `json:"network"`  ／* networkDriver name *／
    Endpoint string `json:"endpoint"`
    State    string `json:"state"`  /* stateDriver name */
}

// Init initializes the NetPlugin instance via the configuration string passed.
func (p *NetPlugin) Init(pluginConfig Config) error {
    // initialize state driver
    p.StateDriver, err = utils.GetStateDriver() /* etcd or consul */

    // initialize network driver
    p.NetworkDriver, err = utils.NewNetworkDriver(pluginConfig.Drivers.Network, &pluginConfig.Instance) /* ovs or vpp */

    p.PluginConfig = pluginConfig
}

### 启动 cni plugin server

cni plugin server 为 cni plugin 创建／删除 Pod 网络。

**mgmtfn/k8splugin/cniserver.go**

// InitCNIServer initializes the k8s cni server
func InitCNIServer(netplugin *plugin.NetPlugin) error {

    netPlugin = netplugin
    hostname, err := os.Hostname()
    if err != nil {
        log.Fatalf("Could not retrieve hostname: %v", err)
    }

    pluginHost = hostname

    // Set up the api client instance
    kubeAPIClient = setUpAPIClient()
    if kubeAPIClient == nil {
        log.Fatalf("Could not init kubernetes API client")
    }

    log.Debugf("Configuring router")

    router := mux.NewRouter()

    // register handlers for cni
    t := router.Headers("Content-Type", "application/json").Methods("POST").Subrouter()
    t.HandleFunc(cniapi.EPAddURL, utils.MakeHTTPHandler(addPod))
    t.HandleFunc(cniapi.EPDelURL, utils.MakeHTTPHandler(deletePod))
    t.HandleFunc("/ContivCNI.{*}", utils.UnknownAction)

    driverPath := cniapi.ContivCniSocket
    os.Remove(driverPath)
    os.MkdirAll(cniapi.PluginPath, 0700)

    go func() {
        l, err := net.ListenUnix("unix", &net.UnixAddr{Name: driverPath, Net: "unix"})
        if err != nil {
            panic(err)
        }

        log.Infof("k8s plugin listening on %s", driverPath)
        http.Serve(l, router)
        l.Close()
        log.Infof("k8s plugin closing %s", driverPath)
    }()

    //InitKubServiceWatch(netplugin)
    return nil
}

## 根据 Node 当前状态更新 Node 环境环境

**netplugin/agent/agent.go**

// ProcessCurrentState processes current state as read from stateStore
func (ag *Agent) ProcessCurrentState() error {
    opts := ag.pluginConfig.Instance
    readNet := &mastercfg.CfgNetworkState{}
    readNet.StateDriver = ag.netPlugin.StateDriver
    // 从 state store 获取 network 状态信息
    netCfgs, err := readNet.ReadAll()
    if err == nil {
        // 根据 network 信息更新 Node ovs 状态
        for idx, netCfg := range netCfgs {
            net := netCfg.(*mastercfg.CfgNetworkState)
            log.Debugf("read net key[%d] %s, populating state \n", idx, net.ID)
            // Node 上添加 network
            processNetEvent(ag.netPlugin, net, false, opts)
            if net.NwType == "infra" {
                // 如果为 infra 网络类型，需要在 Node 上创建一个虚拟 interface
                processInfraNwCreate(ag.netPlugin, net, opts)
            }
        }
    }

    readEp := &mastercfg.CfgEndpointState{}
    readEp.StateDriver = ag.netPlugin.StateDriver
    // 从 state store 获取 endpoint 状态信息
    epCfgs, err := readEp.ReadAll()
    if err == nil {
        // 根据 endpoint 信息更新 Node ovs 状态
        for idx, epCfg := range epCfgs {
            ep := epCfg.(*mastercfg.CfgEndpointState)
            log.Debugf("read ep key[%d] %s, populating state \n", idx, ep.ID)
            // Node 上更新 endpoint 状态
            processEpState(ag.netPlugin, opts, ep.ID)
        }
    }

    readBgp := &mastercfg.CfgBgpState{}
    readBgp.StateDriver = ag.netPlugin.StateDriver
    // 从 state store 获取 bgp 状态信息
    bgpCfgs, err := readBgp.ReadAll()
    if err == nil {
        // 根据 endpoint 信息更新 Node bgp 状态
        for idx, bgpCfg := range bgpCfgs {
            bgp := bgpCfg.(*mastercfg.CfgBgpState)
            log.Debugf("read bgp key[%d] %s, populating state \n", idx, bgp.Hostname)
            // Node 上添加 bgp neighbor
            processBgpEvent(ag.netPlugin, opts, bgp.Hostname, false)
        }
    }

    readEpg := mastercfg.EndpointGroupState{}
    readEpg.StateDriver = ag.netPlugin.StateDriver
    // 从 state store 获取 endpoint group 状态信息
    epgCfgs, err := readEpg.ReadAll()
    if err == nil {
        // 根据 endpoint group 信息更新新 Node ovs 状态
        for idx, epgCfg := range epgCfgs {
            epg := epgCfg.(*mastercfg.EndpointGroupState)
            log.Infof("Read epg key[%d] %s, populating state \n", idx, epg.GroupName)
            // Node 上添加 endpoint group
            processEpgEvent(ag.netPlugin, opts, epg.ID, false)
        }
    }

    // kubernetes 模式可以忽略
    readServiceLb := &mastercfg.CfgServiceLBState{}
    readServiceLb.StateDriver = ag.netPlugin.StateDriver
    serviceLbCfgs, err := readServiceLb.ReadAll()
    if err == nil {
        for idx, serviceLbCfg := range serviceLbCfgs {
            serviceLb := serviceLbCfg.(*mastercfg.CfgServiceLBState)
            log.Debugf("read svc key[%d] %s for tenant %s, populating state \n", idx,
                serviceLb.ServiceName, serviceLb.Tenant)
            processServiceLBEvent(ag.netPlugin, serviceLb, false)
        }
    }

    // kubernetes 模式可以忽略
    readSvcProviders := &mastercfg.SvcProvider{}
    readSvcProviders.StateDriver = ag.netPlugin.StateDriver
    svcProviders, err := readSvcProviders.ReadAll()
    if err == nil {
        for idx, providers := range svcProviders {
            svcProvider := providers.(*mastercfg.SvcProvider)
            log.Infof("read svc provider[%d] %s , populating state \n", idx,
                svcProvider.ServiceName)
            processSvcProviderUpdEvent(ag.netPlugin, svcProvider, false)
        }
    }

    return nil
}


### Infra 网络处理

前面说过，contiv 定义了两种网络类型：

- application network：该网络主要给容器使用
- infrastructure network：在 Node 网络空间创建一个虚拟机的网络。比如，该网络可以被部署在 Node 网络空间上的服务（如监控）使用

**netplugin/agent/state_event.go**

// 在 Node ovs 上创建一个 interface，该 interface 可以被 Node 上的其他服务使用
// Process Infra Nw Create
// Auto allocate an endpoint for this node
func processInfraNwCreate(netPlugin *plugin.NetPlugin, nwCfg *mastercfg.CfgNetworkState, opts core.InstanceInfo) (err error) {
    pluginHost := opts.HostLabel

    // Build endpoint request
    mreq := master.CreateEndpointRequest{
        TenantName:  nwCfg.Tenant,
        NetworkName: nwCfg.NetworkName,
        EndpointID:  pluginHost,
        ConfigEP: intent.ConfigEP{
            Container: pluginHost,
            Host:      pluginHost,
        },
    }

    // 向 netmaster 申请一个 endpoint
    var mresp master.CreateEndpointResponse
    err = cluster.MasterPostReq("/plugin/createEndpoint", &mreq, &mresp)
    if err != nil {
        log.Errorf("master failed to create endpoint %s", err)
        return err
    }

    log.Infof("Got endpoint create resp from master: %+v", mresp)

    // Take lock to ensure netPlugin processes only one cmd at a time

    // Ask netplugin to create the endpoint
    netID := nwCfg.NetworkName + "." + nwCfg.Tenant
    err = netPlugin.CreateEndpoint(netID + "-" + pluginHost)
    if err != nil {
        log.Errorf("Endpoint creation failed. Error: %s", err)
        return err
    }

    // Node 上创建一个 interface，并根据 endpoint 信息设置 interface ip
    // Assign IP to interface
    ipCIDR := fmt.Sprintf("%s/%d", mresp.EndpointConfig.IPAddress, nwCfg.SubnetLen)
    err = netutils.SetInterfaceIP(nwCfg.NetworkName, ipCIDR)
    if err != nil {
        log.Errorf("Could not assign ip: %s", err)
        return err
    }

    // 如果为 vxlan 网络，还需要为该 interface 添加 vxlan 路由
    // add host access routes for vxlan networks
    if nwCfg.NetworkName == contivVxGWName {
        addVxGWRoutes(netPlugin, mresp.EndpointConfig.IPAddress)
    }

    return nil
}

### 处理 network event

侦听到 CfgNetworkState 变更事件时，由 processNetEvent 处理。

**netplugin/agent/state_event.go**

func processNetEvent(netPlugin *plugin.NetPlugin, nwCfg *mastercfg.CfgNetworkState,
    isDelete bool, opts core.InstanceInfo) (err error) {
    // take a lock to ensure we are programming one event at a time.
    // Also network create events need to be processed before endpoint creates
    // and reverse shall happen for deletes. That order is ensured by netmaster,
    // so we don't need to worry about that here

    gwIP := ""
    route := fmt.Sprintf("%s/%d", nwCfg.SubnetIP, nwCfg.SubnetLen)
    if nwCfg.NwType != "infra" && nwCfg.PktTagType == "vxlan" {
        gwIP, _ = getVxGWIP(netPlugin, nwCfg.Tenant, opts.HostLabel)
    }
    operStr := ""
    if isDelete {
        err = netPlugin.DeleteNetwork(nwCfg.ID, route, nwCfg.NwType, nwCfg.PktTagType, nwCfg.PktTag, nwCfg.ExtPktTag,
            nwCfg.Gateway, nwCfg.Tenant)
        operStr = "delete"
        if err == nil && gwIP != "" {
            netutils.DelIPRoute(route, gwIP)
        }
    } else {
        err = netPlugin.CreateNetwork(nwCfg.ID)
        operStr = "create"
        if err == nil && gwIP != "" {
            netutils.AddIPRoute(route, gwIP)
        }
    }
    if err != nil {
        log.Errorf("Network %s operation %s failed. Error: %s", nwCfg.ID, operStr, err)
    } else {
        log.Infof("Network %s operation %s succeeded", nwCfg.ID, operStr)
    }

    return
}

**netplugin/plugin/netplugin.go**

// CreateNetwork creates a network for a given ID.
func (p *NetPlugin) CreateNetwork(id string) error {
    p.Lock()
    defer p.Unlock()
    return p.NetworkDriver.CreateNetwork(id)
}

**drivers/ovsd/ovsdriver.go**

// CreateNetwork creates a network by named identifier
func (d *OvsDriver) CreateNetwork(id string) error {
    cfgNw := mastercfg.CfgNetworkState{}
    cfgNw.StateDriver = d.oper.StateDriver
    err := cfgNw.Read(id)
    if err != nil {
        log.Errorf("Failed to read net %s \n", cfgNw.ID)
        return err
    }
    log.Infof("create net %+v \n", cfgNw)

    // Find the switch based on network type
    var sw *OvsSwitch
    if cfgNw.PktTagType == "vxlan" {
        sw = d.switchDb["vxlan"]
    } else {
        sw = d.switchDb["vlan"]
    }

    return sw.CreateNetwork(uint16(cfgNw.PktTag), uint32(cfgNw.ExtPktTag), cfgNw.Gateway, cfgNw.Tenant)
}

**drivers/ovsd/ovsSwitch.go**

// CreateNetwork creates a new network/vlan
func (sw *OvsSwitch) CreateNetwork(pktTag uint16, extPktTag uint32, defaultGw string, Vrf string) error {
    // Add the vlan/vni to ofnet
    if sw.ofnetAgent != nil {
        err := sw.ofnetAgent.AddNetwork(pktTag, extPktTag, defaultGw, Vrf)
        if err != nil {
            log.Errorf("Error adding vlan/vni %d/%d. Err: %v", pktTag, extPktTag, err)
            return err
        }
    }
    return nil
}

### 处理 endpoint event

**netplugin/agent/state_event.go**

// processEpState restores endpoint state
func processEpState(netPlugin *plugin.NetPlugin, opts core.InstanceInfo, epID string) error {
    netPlugin.CreateEndpoint(epID)
}

### func (p *NetPlugin) CreateEndpoint

**netplugin/plugin/netplugin.go**

// CreateEndpoint creates an endpoint for a given ID.
func (p *NetPlugin) CreateEndpoint(id string) error {
    p.Lock()
    defer p.Unlock()
    return p.NetworkDriver.CreateEndpoint(id)
}

**drivers/ovsd/ovsdriver.go**

// CreateEndpoint creates an endpoint by named identifier
func (d *OvsDriver) CreateEndpoint(id string) error {
    var (
        err          error
        intfName     string
        epgKey       string
        epgBandwidth int64
        dscp         int
    )

    cfgEp := &mastercfg.CfgEndpointState{}
    cfgEp.StateDriver = d.oper.StateDriver
    err = cfgEp.Read(id)

    // Get the nw config.
    cfgNw := mastercfg.CfgNetworkState{}
    cfgNw.StateDriver = d.oper.StateDriver
    err = cfgNw.Read(cfgEp.NetID)

    pktTagType := cfgNw.PktTagType
    pktTag := cfgNw.PktTag
    cfgEpGroup := &mastercfg.EndpointGroupState{}
    // Read pkt tags from endpoint group if available
    if cfgEp.EndpointGroupKey != "" {
        cfgEpGroup.StateDriver = d.oper.StateDriver

        err = cfgEpGroup.Read(cfgEp.EndpointGroupKey)
        if err == nil {
            log.Debugf("pktTag: %v ", cfgEpGroup.PktTag)
            pktTagType = cfgEpGroup.PktTagType
            pktTag = cfgEpGroup.PktTag
            epgKey = cfgEp.EndpointGroupKey
            dscp = cfgEpGroup.DSCP
            if cfgEpGroup.Bandwidth != "" {
                epgBandwidth = netutils.ConvertBandwidth(cfgEpGroup.Bandwidth)
            }

        } else if core.ErrIfKeyExists(err) == nil {
            log.Infof("EPG %s not found: %v. will use network based tag ", cfgEp.EndpointGroupKey, err)
        } else {
            return err
        }
    }

    // Find the switch based on network type
    var sw *OvsSwitch
    if pktTagType == "vxlan" {
        sw = d.switchDb["vxlan"]
    } else {
        sw = d.switchDb["vlan"]
    }

    // Skip Veth pair creation for infra nw endpoints
    skipVethPair := (cfgNw.NwType == "infra")

    operEp := &drivers.OperEndpointState{}
    operEp.StateDriver = d.oper.StateDriver
    err = operEp.Read(id)
    if core.ErrIfKeyExists(err) != nil {
        return err
    } else if err == nil {
        // check if oper state matches cfg state. In case of mismatch cleanup
        // up the EP and continue add new one. In case of match just return.
        if operEp.Matches(cfgEp) {
            log.Printf("Found matching oper state for ep %s, noop", id)

            // Ask the switch to update the port
            err = sw.UpdatePort(operEp.PortName, cfgEp, pktTag, cfgNw.PktTag, dscp, skipVethPair)
            if err != nil {
                log.Errorf("Error creating port %s. Err: %v", intfName, err)
                return err
            }

            return nil
        }
        log.Printf("Found mismatching oper state for Ep, cleaning it. Config: %+v, Oper: %+v",
            cfgEp, operEp)
        d.DeleteEndpoint(operEp.ID)
    }

    if cfgNw.NwType == "infra" {
        // For infra nw, port name is network name
        intfName = cfgNw.NetworkName
    } else {
        // Get the interface name to use
        intfName, err = d.getIntfName()
        if err != nil {
            return err
        }
    }

    // Get OVS port name
    ovsPortName := getOvsPortName(intfName, skipVethPair)

    // Ask the switch to create the port
    err = sw.CreatePort(intfName, cfgEp, pktTag, cfgNw.PktTag, cfgEpGroup.Burst, dscp, skipVethPair, epgBandwidth)
    if err != nil {
        log.Errorf("Error creating port %s. Err: %v", intfName, err)
        return err
    }

    // save local endpoint info
    d.oper.localEpInfoMutex.Lock()
    d.oper.LocalEpInfo[id] = &EpInfo{
        Ovsportname: ovsPortName,
        EpgKey:      epgKey,
        BridgeType:  pktTagType,
    }
    d.oper.localEpInfoMutex.Unlock()
    err = d.oper.Write()
    if err != nil {
        return err
    }
    // Save the oper state
    operEp = &drivers.OperEndpointState{
        NetID:       cfgEp.NetID,
        EndpointID:  cfgEp.EndpointID,
        ServiceName: cfgEp.ServiceName,
        IPAddress:   cfgEp.IPAddress,
        IPv6Address: cfgEp.IPv6Address,
        MacAddress:  cfgEp.MacAddress,
        IntfName:    cfgEp.IntfName,
        PortName:    intfName,
        HomingHost:  cfgEp.HomingHost,
        VtepIP:      cfgEp.VtepIP}
    operEp.StateDriver = d.oper.StateDriver
    operEp.ID = id
    err = operEp.Write()
    if err != nil {
        return err
    }

    defer func() {
        if err != nil {
            operEp.Clear()
        }
    }()
    return nil
}

### 处理 bgp event

**netplugin/agent/state_event.go**

//processBgpEvent processes Bgp neighbor add/delete events
func processBgpEvent(netPlugin *plugin.NetPlugin, opts core.InstanceInfo, hostID string, isDelete bool) error {
    var err error

    if opts.HostLabel != hostID {
        log.Debugf("Ignoring Bgp Event on this host")
        return err
    }

    operStr := ""
    if isDelete {
        err = netPlugin.DeleteBgp(hostID)
        operStr = "delete"
    } else {
        err = netPlugin.AddBgp(hostID)
        operStr = "create"
    }
    if err != nil {
        log.Errorf("Bgp operation %s failed. Error: %s", operStr, err)
    } else {
        log.Infof("Bgp operation %s succeeded", operStr)
    }

    return err
}


### 处理 enpoint group event

**netplugin/agent/state_event.go**

func processEpgEvent(netPlugin *plugin.NetPlugin, opts core.InstanceInfo, ID string, isDelete bool) error {
    log.Infof("Received processEpgEvent")
    var err error

    operStr := ""
    if isDelete {
        operStr = "delete"
    } else {
        err = netPlugin.UpdateEndpointGroup(ID)
        operStr = "update"
    }
    if err != nil {
        log.Errorf("Epg %s failed. Error: %s", operStr, err)
    } else {
        log.Infof("Epg %s succeeded", operStr)
    }

    return err
}


### 处理 servicelb event

**netplugin/agent/state_event.go**

//processServiceLBEvent processes service load balancer object events
func processServiceLBEvent(netPlugin *plugin.NetPlugin, svcLBCfg *mastercfg.CfgServiceLBState, isDelete bool) error {
    var err error
    portSpecList := []core.PortSpec{}
    portSpec := core.PortSpec{}

    serviceID := svcLBCfg.ID

    log.Infof("Recevied Process Service load balancer event {%v}", svcLBCfg)

    //create portspect list from state.
    //Ports format: servicePort:ProviderPort:Protocol
    for _, port := range svcLBCfg.Ports {

        portInfo := strings.Split(port, ":")
        if len(portInfo) != 3 {
            return errors.New("invalid Port Format")
        }
        svcPort := portInfo[0]
        provPort := portInfo[1]
        portSpec.Protocol = portInfo[2]

        sPort, _ := strconv.ParseUint(svcPort, 10, 16)
        portSpec.SvcPort = uint16(sPort)

        pPort, _ := strconv.ParseUint(provPort, 10, 16)
        portSpec.ProvPort = uint16(pPort)

        portSpecList = append(portSpecList, portSpec)
    }

    spec := &core.ServiceSpec{
        IPAddress: svcLBCfg.IPAddress,
        Ports:     portSpecList,
    }

    operStr := ""
    if isDelete {
        err = netPlugin.DeleteServiceLB(serviceID, spec)
        operStr = "delete"
    } else {
        err = netPlugin.AddServiceLB(serviceID, spec)
        operStr = "create"
    }
    if err != nil {
        log.Errorf("Service Load Balancer %s failed.Error:%s", operStr, err)
        return err
    }
    log.Infof("Service Load Balancer %s succeeded", operStr)

    return nil
}

**netplugin/plugin/netplugin.go**

//AddServiceLB adds service
func (p *NetPlugin) AddServiceLB(servicename string, spec *core.ServiceSpec) error {
    p.Lock()
    defer p.Unlock()
    return p.NetworkDriver.AddSvcSpec(servicename, spec)
}

**drivers/ovsd/ovsdriver.go**

// AddSvcSpec invokes switch api
func (d *OvsDriver) AddSvcSpec(svcName string, spec *core.ServiceSpec) error {
    log.Infof("AddSvcSpec: %s", svcName)
    ss := convSvcSpec(spec)
    errs := ""
    // ovs 交换机上添加 service vip 负载均衡到后端 pod 的规则
    // 主要用于 pod -> service 的网络流向
    for _, sw := range d.switchDb {
        log.Infof("sw AddSvcSpec: %s", svcName)
        err := sw.AddSvcSpec(svcName, ss)
        if err != nil {
            errs += err.Error()
        }
    }

    // Node iptables 上添加 service vip 负载均衡到后端 pod 的规则
    // 主要用于外部／主机管理网 -> service 的网络流向
    err := d.HostProxy.AddSvcSpec(svcName, spec)
    if err != nil {
        errs += err.Error()
    }

    if errs != "" {
        return errors.New(errs)
    }

    // 添加域名绑定到 inline nameserver
    d.nameServer.AddLbService(nameserver.K8sDefaultTenant, svcName, spec.IPAddress)

    return nil
}


## 处理 service provider update event

**netplugin/agent/state_event.go**

//processSvcProviderUpdEvent updates service provider events
func processSvcProviderUpdEvent(netPlugin *plugin.NetPlugin, svcProvider *mastercfg.SvcProvider, isDelete bool) error {
    if isDelete {
        //ignore delete event since servicelb delete will take care of this.
        return nil
    }
    netPlugin.SvcProviderUpdate(svcProvider.ServiceName, svcProvider.Providers)
    return nil
}

**netplugin/plugin/netplugin.go**

//SvcProviderUpdate function
func (p *NetPlugin) SvcProviderUpdate(servicename string, providers []string) {
    p.Lock()
    defer p.Unlock()
    p.NetworkDriver.SvcProviderUpdate(servicename, providers)
}

**drivers/ovsd/ovsdriver.go**

// SvcProviderUpdate invokes switch api
func (d *OvsDriver) SvcProviderUpdate(svcName string, providers []string) {
    // ovs 交换机上更新 service vip 负载均衡到后端 pod 的规则
    for _, sw := range d.switchDb {
        sw.SvcProviderUpdate(svcName, providers)
    }

    // Node iptables 上更新 service vip 负载均衡到后端 pod 的规则
    d.HostProxy.SvcProviderUpdate(svcName, providers)
}

## 侦听 cluster 中 Netplugin 实例和 Netmaster 实例变化，提供 Netplugin 实例的状态信息接口和调试接口

**netplugin/agent/agent.go**

// PostInit post initialization
func (ag *Agent) PostInit() error {
    opts := ag.pluginConfig.Instance

    // Initialize clustering
    // 1. 将 Netplugin 实例 Service 添加到 cluster
    // 2. 侦听 cluster 中 Netplugin 实例和 Netmaster 实例变更（add／delete），
    //   根据变更信息更新该 Netplugin 实例所在 Node 的网络信息
    err := cluster.RunLoop(ag.netPlugin, opts.CtrlIP, opts.VtepIP, opts.HostLabel)
    if err != nil {
        log.Errorf("Error starting cluster run loop")
    }

    // Netplugin 实例启动一个 restful api 服务，提供暴露 Netplugin 实例的状态信息
    // 和调试接口
    // start service REST requests
    ag.serveRequests()

    return nil
}

**netplugin/cluster/cluster.go**

// RunLoop registers netplugin service with cluster store and runs peer discovery
func RunLoop(netplugin *plugin.NetPlugin, ctrlIP, vtepIP, hostname string) error {
    // Register ourselves
    err := registerService(ObjdbClient, ctrlIP, vtepIP, hostname, netplugin.PluginConfig.Instance.VxlanUDPPort)

    // Start peer discovery loop
    go peerDiscoveryLoop(netplugin, ObjdbClient, ctrlIP, vtepIP)

    return err
}

// Main loop to discover peer hosts and masters
func peerDiscoveryLoop(netplugin *plugin.NetPlugin, objClient objdb.API, ctrlIP, vtepIP string) {
    // Create channels for watch thread
    nodeEventCh := make(chan objdb.WatchServiceEvent, 1)
    watchStopCh := make(chan bool, 1)
    masterEventCh := make(chan objdb.WatchServiceEvent, 1)
    masterWatchStopCh := make(chan bool, 1)

    // Start a watch on netmaster
    err := objClient.WatchService("netmaster.rpc", masterEventCh, masterWatchStopCh)
    if err != nil {
        log.Fatalf("Could not start a watch on netmaster service. Err: %v", err)
    }

    // Start a watch on netplugin service
    err = objClient.WatchService("netplugin.vtep", nodeEventCh, watchStopCh)
    if err != nil {
        log.Fatalf("Could not start a watch on netplugin service. Err: %v", err)
    }

    for {
        select {
        case srvEvent := <-nodeEventCh:
            log.Debugf("Received netplugin service watch event: %+v", srvEvent)

            // collect the info about the node
            nodeInfo := srvEvent.ServiceInfo

            // check if its our own info coming back to us
            if nodeInfo.HostAddr == vtepIP {
                break
            }

            // Handle based on event type
            if srvEvent.EventType == objdb.WatchServiceEventAdd {
                log.Infof("Node add event for {%+v}", nodeInfo)

                // add the node
                err := netplugin.AddPeerHost(core.ServiceInfo{
                    HostAddr: nodeInfo.HostAddr,
                    Port:     netplugin.PluginConfig.Instance.VxlanUDPPort,
                })
                if err != nil {
                    log.Errorf("Error adding node {%+v}. Err: %v", nodeInfo, err)
                }
            } else if srvEvent.EventType == objdb.WatchServiceEventDel {
                log.Infof("Node delete event for {%+v}", nodeInfo)

                // remove the node
                err := netplugin.DeletePeerHost(core.ServiceInfo{
                    HostAddr: nodeInfo.HostAddr,
                    Port:     netplugin.PluginConfig.Instance.VxlanUDPPort,
                })
                if err != nil {
                    log.Errorf("Error deleting node {%+v}. Err: %v", nodeInfo, err)
                }
            }
        case srvEvent := <-masterEventCh:
            log.Infof("Received netmaster service watch event: %+v", srvEvent)

            // collect the info about the node
            nodeInfo := srvEvent.ServiceInfo

            // Handle based on event type
            if srvEvent.EventType == objdb.WatchServiceEventAdd {
                log.Infof("Master add event for {%+v}", nodeInfo)

                // Add the master
                err := addMaster(netplugin, nodeInfo)
                if err != nil {
                    log.Errorf("Error adding master {%+v}. Err: %v", nodeInfo, err)
                }
            } else if srvEvent.EventType == objdb.WatchServiceEventDel {
                log.Infof("Master delete event for {%+v}", nodeInfo)

                // Delete the master
                err := deleteMaster(netplugin, nodeInfo)
                if err != nil {
                    log.Errorf("Error deleting master {%+v}. Err: %v", nodeInfo, err)
                }
            }
        }

        // Dont process next peer event for another 100ms
        time.Sleep(100 * time.Millisecond)
    }
}

**netplugin/agent/agent.go**

// serveRequests serve REST api requests
func (ag *Agent) serveRequests() {
    listenURL := ":9090"
    router := mux.NewRouter()

    // Add REST routes
    s := router.Methods("GET").Subrouter()
    s.HandleFunc("/svcstats", func(w http.ResponseWriter, r *http.Request) {
        stats, err := ag.netPlugin.GetEndpointStats()
        if err != nil {
            log.Errorf("Error fetching stats from driver. Err: %v", err)
            http.Error(w, "Error fetching stats from driver", http.StatusInternalServerError)
            return
        }
        w.Header().Set("Content-Type", "application/json")
        w.Write(stats)
    })
    s.HandleFunc("/inspect/driver", func(w http.ResponseWriter, r *http.Request) {
        driverState, err := ag.netPlugin.InspectState()
        if err != nil {
            log.Errorf("Error fetching driver state. Err: %v", err)
            http.Error(w, "Error fetching driver state", http.StatusInternalServerError)
            return
        }
        w.Write(driverState)
    })
    s.HandleFunc("/inspect/bgp", func(w http.ResponseWriter, r *http.Request) {
        bgpState, err := ag.netPlugin.InspectBgp()
        if err != nil {
            log.Errorf("Error fetching bgp. Err: %v", err)
            http.Error(w, "Error fetching bgp", http.StatusInternalServerError)
            return
        }
        w.Write(bgpState)
    })

    s.HandleFunc("/inspect/nameserver", func(w http.ResponseWriter, r *http.Request) {
        ns, err := ag.netPlugin.NetworkDriver.InspectNameserver()
        if err != nil {
            log.Errorf("Error fetching nameserver state. Err: %v", err)
            http.Error(w, "Error fetching nameserver state", http.StatusInternalServerError)
            return
        }
        w.Write(ns)
    })

    s = router.Methods("Delete").Subrouter()
    s.HandleFunc("/debug/reclaimEndpoint/{id}", utils.MakeHTTPHandler(ag.ReclaimEndpointHandler))

    // Create HTTP server and listener
    server := &http.Server{Handler: router}
    listener, err := net.Listen("tcp", listenURL)
    if nil != err {
        log.Fatalln(err)
    }

    log.Infof("Netplugin listening on %s", listenURL)

    // start server
    go server.Serve(listener)
}

## netplugin wait 等待处理各种 event

**netplugin/agent/agent.go**

// HandleEvents handles events
func (ag *Agent) HandleEvents() error {
    opts := ag.pluginConfig.Instance
    recvErr := make(chan error, 1)

    go handleNetworkEvents(ag.netPlugin, opts, recvErr)

    go handleBgpEvents(ag.netPlugin, opts, recvErr)

    go handleEndpointEvents(ag.netPlugin, opts, recvErr)

    go handleEpgEvents(ag.netPlugin, opts, recvErr)

    go handleServiceLBEvents(ag.netPlugin, opts, recvErr)

    go handleSvcProviderUpdEvents(ag.netPlugin, opts, recvErr)

    go handleGlobalCfgEvents(ag.netPlugin, opts, recvErr)

    go handlePolicyRuleEvents(ag.netPlugin, opts, recvErr)

    if ag.pluginConfig.Instance.PluginMode == core.Docker ||
        ag.pluginConfig.Instance.PluginMode == core.SwarmMode {
        go ag.monitorDockerEvents(recvErr)
    } else if ag.pluginConfig.Instance.PluginMode == core.Kubernetes {
        // watch k8s service 和 endpoint 变化并更新 Node 网络信息
        // start watching kubernetes events
        k8splugin.InitKubServiceWatch(ag.netPlugin)
    }
    err := <-recvErr
    if err != nil {
        time.Sleep(1 * time.Second)
        log.Errorf("Failure occurred. Error: %s", err)
        return err
    }

    return nil
}

### 等待接受网络变更信息，更新 Node 网络状态

下列线程：

- go handleNetworkEvents(ag.netPlugin, opts, recvErr)
- go handleBgpEvents(ag.netPlugin, opts, recvErr)
- go handleEndpointEvents(ag.netPlugin, opts, recvErr)
- go handleEpgEvents(ag.netPlugin, opts, recvErr)
- go handleServiceLBEvents(ag.netPlugin, opts, recvErr)
- go handleSvcProviderUpdEvents(ag.netPlugin, opts, recvErr)
- go handleGlobalCfgEvents(ag.netPlugin, opts, recvErr)
- go handlePolicyRuleEvents(ag.netPlugin, opts, recvErr)

上述线程都调用 processStateEvent 处理网络状态变更。

另外说明一点：network、bgp、endpoint、endpointGroup、serviceLB、serviceProvider、policyRule 都是由 netmaster 创建的；globalConfig 也是通过 netmaster 更改的。

**netplugin/agent/state_event.go**

func processStateEvent(netPlugin *plugin.NetPlugin, opts core.InstanceInfo, rsps chan core.WatchState) {
    for {
        // block on change notifications
        rsp := <-rsps

        // For now we deal with only create and delete events
        currentState := rsp.Curr
        isDelete := false
        eventStr := "create"
        if rsp.Curr == nil {
            currentState = rsp.Prev
            isDelete = true
            eventStr = "delete"
        } else if rsp.Prev != nil {
            if bgpCfg, ok := currentState.(*mastercfg.CfgBgpState); ok {
                log.Infof("Received %q for Bgp: %q", eventStr, bgpCfg.Hostname)
                processBgpEvent(netPlugin, opts, bgpCfg.Hostname, isDelete)
                continue
            }

            if epgCfg, ok := currentState.(*mastercfg.EndpointGroupState); ok {
                log.Infof("Received %q for Endpointgroup: %q", eventStr, epgCfg.EndpointGroupID)
                processEpgEvent(netPlugin, opts, epgCfg.ID, isDelete)
                continue
            }

            if svcProvider, ok := currentState.(*mastercfg.SvcProvider); ok {
                log.Infof("Received %q for Service %s , provider:%#v", eventStr,
                    svcProvider.ServiceName, svcProvider.Providers)
                processSvcProviderUpdEvent(netPlugin, svcProvider, isDelete)
            }

            if gCfg, ok := currentState.(*mastercfg.GlobConfig); ok {
                prevCfg := rsp.Prev.(*mastercfg.GlobConfig)
                log.Infof("Received %q for global config current state - %+v, prev state - %+v ", eventStr,
                    gCfg, prevCfg)
                processGlobalConfigUpdEvent(netPlugin, opts, prevCfg, gCfg)
            }

            // Ignore modify event on network state
            if nwCfg, ok := currentState.(*mastercfg.CfgNetworkState); ok {
                log.Debugf("Received a modify event on network %q, ignoring it", nwCfg.ID)
                continue
            }

        }

        if nwCfg, ok := currentState.(*mastercfg.CfgNetworkState); ok {
            log.Infof("Received %q for network: %q", eventStr, nwCfg.ID)
            if isDelete != true {
                processNetEvent(netPlugin, nwCfg, isDelete, opts)
                if nwCfg.NwType == "infra" {
                    processInfraNwCreate(netPlugin, nwCfg, opts)
                }
            } else {
                if nwCfg.NwType == "infra" {
                    processInfraNwDelete(netPlugin, nwCfg, opts)
                }
                processNetEvent(netPlugin, nwCfg, isDelete, opts)
            }
        }
        if epCfg, ok := currentState.(*mastercfg.CfgEndpointState); ok {
            log.Infof("Received %q for Endpoint: %q", eventStr, epCfg.ID)
            processRemoteEpState(netPlugin, opts, epCfg, isDelete)
        }
        if bgpCfg, ok := currentState.(*mastercfg.CfgBgpState); ok {
            log.Infof("Received %q for Bgp: %q", eventStr, bgpCfg.Hostname)
            processBgpEvent(netPlugin, opts, bgpCfg.Hostname, isDelete)
        }
        if epgCfg, ok := currentState.(*mastercfg.EndpointGroupState); ok {
            log.Infof("Received %q for Endpointgroup: %q", eventStr, epgCfg.EndpointGroupID)
            processEpgEvent(netPlugin, opts, epgCfg.ID, isDelete)
            continue
        }
        if serviceLbCfg, ok := currentState.(*mastercfg.CfgServiceLBState); ok {
            log.Infof("Received %q for Service %s on tenant %s", eventStr,
                serviceLbCfg.ServiceName, serviceLbCfg.Tenant)
            processServiceLBEvent(netPlugin, serviceLbCfg, isDelete)
        }
        if svcProvider, ok := currentState.(*mastercfg.SvcProvider); ok {
            log.Infof("Received %q for Service %s on tenant %s", eventStr,
                svcProvider.ServiceName, svcProvider.Providers)
            processSvcProviderUpdEvent(netPlugin, svcProvider, isDelete)
        }
        if ruleCfg, ok := currentState.(*mastercfg.CfgPolicyRule); ok {
            log.Infof("Received %q for PolicyRule: %q", eventStr, ruleCfg.RuleId)
            processPolicyRuleState(netPlugin, opts, ruleCfg.RuleId, isDelete)
        }
    }
}

#### processEpgEvent

**netplugin/agent/state_event.go**

func processEpgEvent(netPlugin *plugin.NetPlugin, opts core.InstanceInfo, ID string, isDelete bool) error {
    log.Infof("Received processEpgEvent")
    var err error

    operStr := ""
    if isDelete {
        operStr = "delete"
    } else {
        err = netPlugin.UpdateEndpointGroup(ID)
        operStr = "update"
    }
    if err != nil {
        log.Errorf("Epg %s failed. Error: %s", operStr, err)
    } else {
        log.Infof("Epg %s succeeded", operStr)
    }

    return err
}

**netplugin/plugin/netplugin.go**

//UpdateEndpointGroup updates the endpoint with the new endpointgroup specification for the given ID.
func (p *NetPlugin) UpdateEndpointGroup(id string) error {
    p.Lock()
    defer p.Unlock()
    return p.NetworkDriver.UpdateEndpointGroup(id)
}

**drivers/ovsd/ovsdriver.go**

//UpdateEndpointGroup updates the epg
func (d *OvsDriver) UpdateEndpointGroup(id string) error {
    log.Infof("Received endpoint group update for %s", id)
    var (
        err          error
        epgBandwidth int64
        sw           *OvsSwitch
    )
    //gets the EndpointGroupState object
    cfgEpGroup := &mastercfg.EndpointGroupState{}
    cfgEpGroup.StateDriver = d.oper.StateDriver
    err = cfgEpGroup.Read(id)

    if cfgEpGroup.ID != "" {
        if cfgEpGroup.Bandwidth != "" {
            epgBandwidth = netutils.ConvertBandwidth(cfgEpGroup.Bandwidth)
        }

        d.oper.localEpInfoMutex.Lock()
        defer d.oper.localEpInfoMutex.Unlock()
        for _, epInfo := range d.oper.LocalEpInfo {
            if epInfo.EpgKey == id {
                log.Debugf("Applying bandwidth: %s on: %s ", cfgEpGroup.Bandwidth, epInfo.Ovsportname)
                // Find the switch based on network type
                if epInfo.BridgeType == "vxlan" {
                    sw = d.switchDb["vxlan"]
                } else {
                    sw = d.switchDb["vlan"]
                }

                // update the endpoint in ovs switch
                err = sw.UpdateEndpoint(epInfo.Ovsportname, cfgEpGroup.Burst, cfgEpGroup.DSCP, epgBandwidth)
                if err != nil {
                    log.Errorf("Error adding bandwidth %v , err: %+v", epgBandwidth, err)
                    return err
                }
            }
        }
    }
    return err
}

**drivers/ovsd/ovsSwitch.go**

// UpdateEndpoint updates endpoint state
func (sw *OvsSwitch) UpdateEndpoint(ovsPortName string, burst, dscp int, epgBandwidth int64) error {
    // update bandwidth
    err := sw.ovsdbDriver.UpdatePolicingRate(ovsPortName, burst, epgBandwidth)

    // Get the openflow port number for the interface
    ofpPort, err := sw.ovsdbDriver.GetOfpPortNo(ovsPortName)

    // Build the updated endpoint info
    endpoint := ofnet.EndpointInfo{
        PortNo: ofpPort,
        Dscp:   dscp,
    }

    // update endpoint state in ofnet
    err = sw.ofnetAgent.UpdateLocalEndpoint(endpoint)

    return nil
}

**contiv/ofnet/ofnetAgent.go**

// UpdateLocalEndpoint update state on a local endpoint
func (self *OfnetAgent) UpdateLocalEndpoint(endpoint EndpointInfo) error {
    log.Infof("Received local endpoint update: {%+v}", endpoint)

    // increment stats
    self.incrStats("UpdateLocalEndpoint")

    // find the local endpoint first
    epreg, _ := self.localEndpointDb.Get(string(endpoint.PortNo))
    ep := epreg.(*OfnetEndpoint)

    // datapath 比如：vlan、vxlan 等
    // pass it down to datapath
    err := self.datapath.UpdateLocalEndpoint(ep, endpoint)

    return nil
}

#### processRemoteEpState

这里需要说明的是 `processRemoteEpState` 会去判断 `endpoint` 为 `local` 还是 `remote`：如果为 `local` 就直接忽略，因为 `kubelet` 调用 `cni` 插件创建 `pod` 的时候，通过 `netplugin` 实例向 `netmaster` 申请创建 `local endpoint`、`netplugin` 实例调用 network driver 申请创建 `local endpoint`，并且将 pod 添加到 contiv 网络，所以，即使 netmaster 创建好了之后写了 `etcd`，流程触发走到这里，对于 `local endpoint` 也不需要做其他事情了，所以这里会忽略。

**netplugin/agent/state_event.go**

// processRemoteEpState updates endpoint state
func processRemoteEpState(netPlugin *plugin.NetPlugin, opts core.InstanceInfo, epCfg *mastercfg.CfgEndpointState, isDelete bool) error {
    // 忽略 local endpoint，因为 kubelet 调用 cni 插件创建 pod 的时候
    // 已经处理过 local endpoint 了
    if !checkRemoteHost(epCfg.VtepIP, epCfg.HomingHost, opts.HostLabel) {
        // Skip local endpoint update, as they are handled directly in dockplugin
        return nil
    }

    if isDelete {
        // Delete remote endpoint
        err := netPlugin.DeleteRemoteEndpoint(epCfg.ID)
        if err != nil {
            log.Errorf("Endpoint %s delete operation failed. Error: %s", epCfg.ID, err)
            return err
        }
        log.Infof("Endpoint %s delete operation succeeded", epCfg.ID)
    } else {
        // Create remote endpoint
        err := netPlugin.CreateRemoteEndpoint(epCfg.ID)
        if err != nil {
            log.Errorf("Endpoint %s create operation failed. Error: %s", epCfg.ID, err)
            return err
        }
        log.Infof("Endpoint %s create operation succeeded", epCfg.ID)
    }

    return nil
}

**netplugin/plugin/netplugin.go**

// CreateRemoteEndpoint creates an endpoint for a given ID.
func (p *NetPlugin) CreateRemoteEndpoint(id string) error {
    p.Lock()
    defer p.Unlock()
    return p.NetworkDriver.CreateRemoteEndpoint(id)
}

**drivers/ovsd/ovsdriver.go**

// CreateRemoteEndpoint creates a remote endpoint by named identifier
func (d *OvsDriver) CreateRemoteEndpoint(id string) error {

    log.Debug("OVS driver ignoring remote EP create as it uses its own EP sync")
    return nil
}

### watch k8s service 和 endpoint 变化并更新 Node 网络信息

**netplugin/mgmtfn/k8splugin/cniserver.go**

// InitKubServiceWatch initializes the k8s service watch
func InitKubServiceWatch(np *plugin.NetPlugin) {

    watchClient := setUpAPIClient()
    if watchClient == nil {
        log.Fatalf("Could not init kubernetes API client")
    }

    svcCh := make(chan SvcWatchResp, 1)
    epCh := make(chan EpWatchResp, 1)
    go func() {
        for {
            select {
            // 从 svcCh channel 获取k8s service 变化信息
            // 根据 k8s service 变化更新 Node 网络信息
            case svcEvent := <-svcCh:
                switch svcEvent.opcode {
                case "WARN":
                    log.Debugf("svcWatch : %s", svcEvent.errStr)
                    break
                case "FATAL":
                    log.Errorf("svcWatch : %s", svcEvent.errStr)
                    break
                case "ERROR":
                    log.Warnf("svcWatch : %s", svcEvent.errStr)
                    watchClient.WatchServices(svcCh)
                    break

                case "DELETED":
                    // 最终调用 NetworkDriver DelSvcSpec
                    np.DelSvcSpec(svcEvent.svcName, &svcEvent.svcSpec)
                    break
                default:
                    // 最终调用 NetworkDriver AddSvcSpec
                    np.AddSvcSpec(svcEvent.svcName, &svcEvent.svcSpec)
                }
            // 从 epCh channel 获取k8s endpoint 变化信息
            // 根据 k8s endpoint 变化更新 Node 网络信息
            case epEvent := <-epCh:
                switch epEvent.opcode {
                case "WARN":
                    log.Debugf("epWatch : %s", epEvent.errStr)
                    break
                case "FATAL":
                    log.Errorf("epWatch : %s", epEvent.errStr)
                    break
                case "ERROR":
                    log.Warnf("epWatch : %s", epEvent.errStr)
                    watchClient.WatchSvcEps(epCh)
                    break

                default:
                    np.SvcProviderUpdate(epEvent.svcName, epEvent.providers)
                }
            }
        }
    }()

    // watch k8s service 变化，并将变化信息传人 svcCh channel
    watchClient.WatchServices(svcCh)
    // watch k8s endpoint 变化，并将变化信息传人 epCh channel
    watchClient.WatchSvcEps(epCh)
}

#### K8S Service vs Contiv ServiceLB
watch 到 serviceLB 的处理流程和 `InitKubServiceWatch` 中 watch 到 k8s service 流程基本上一样的：

- netmaster 上创建 serviceLB 流程

netctl -> httpCreateServiceLB -> CreateServiceLB -> (apiController) ServiceLBCreate -> ( master) CreateServiceLB -> (servicelb) CreateServiceLB -> (serviceLbState) Write -> (StateDriver) WriteState -> etcd

- netplugin 上 watch 到 serviceLB 流程

(netplugin agent) processServiceLBEvent -> (netplugin) AddServiceLB -> (NetworkDriver) AddSvcSpec

实际上 k8s 模式下，就用 k8s 的 service 替代了 contiv 的 serviceLB。

- netplugin 上 watch 到 k8s service 的流程

InitKubServiceWatch() -> (netplugin agent) AddSvcSpec -> (NetworkDriver) AddSvcSpec

#### K8S Endpoint vs Contiv ServiceProvider

- netmaster 上创建 serviceProvider 流程

netmaster 并没有提供 restful api 供客户端主动去创建 serviceProvider。即，serviceProvider 不是用户创建的资源。

netmaster 上可能创建 serviceProvider 的地方：

1. CreateServiceLB -> (provider) SvcProviderUpdate -> etcd
2. restful api -> UpdateEndpointHandler -> (provider) SvcProviderUpdate -> etcd

- netplugin 上 watch 到 serviceProvider 流程

handleSvcProviderUpdEvents -> processStateEvent -> processSvcProviderUpdEvent -> (netplugin agent) SvcProviderUpdate -> (NetworkDriver) SvcProviderUpdate

- netplugin 上 watch 到 k8s endpoint 的流程

InitKubServiceWatch() -> (netplugin agent) SvcProviderUpdate -> (NetworkDriver) SvcProviderUpdate

## 将 pod 添加到 contiv 网络

1. 从 pod label 中获取 tenant、network 和 group 信息，构建 contiv endpointSpec
2. 向 netmaster 发送请求创建 contiv endpoint
3. netplugin 通过 network drive 创建 contiv endpoint，比如：network driver 会创建 veth pair
4. 将 interface 添加到 pod，重命名 pod interface 为 eth0，设置 eth0 ip
5. 设置 pod 默认路由

**mgmtfn/k8splugin/driver.go**

// addPod is the handler for pod additions
func addPod(w http.ResponseWriter, r *http.Request, vars map[string]string) (interface{}, error) {

    resp := cniapi.RspAddPod{}

    logEvent("add pod")

    content, err := ioutil.ReadAll(r.Body)
    if err != nil {
        log.Errorf("Failed to read request: %v", err)
        return resp, err
    }

    pInfo := cniapi.CNIPodAttr{}
    if err := json.Unmarshal(content, &pInfo); err != nil {
        return resp, err
    }

    // 1. 从 pod label 中获取 tenant、network 和 group 信息
    // 2. 将 pod 信息包装成一个 contiv endpointSpec
    // Get labels from the kube api server
    epReq, err := getEPSpec(&pInfo)
    if err != nil {
        log.Errorf("Error getting labels. Err: %v", err)
        setErrorResp(&resp, "Error getting labels", err)
        return resp, err
    }

    // 1. 向 netmaster 发送请求创建 contiv endpoint
    // 2. netplugin 通过 network drive 创建 contiv endpoint
    // 3. 返回 epSpec 信息
    ep, err := createEP(epReq)
    if err != nil {
        log.Errorf("Error creating ep. Err: %v", err)
        setErrorResp(&resp, "Error creating EP", err)
        return resp, err
    }

    var epErr error

    defer func() {
        if epErr != nil {
            log.Errorf("error %s, remove endpoint", epErr)
            netPlugin.DeleteHostAccPort(epReq.EndpointID)
            epCleanUp(epReq)
        }
    }()

    // 从 netns 文件路径中获取 pid
    // convert netns to pid that netlink needs
    pid, epErr := nsToPID(pInfo.NwNameSpace)
    if epErr != nil {
        log.Errorf("Error moving to netns. Err: %v", epErr)
        setErrorResp(&resp, "Error moving to netns", epErr)
        return resp, epErr
    }

    // 将 interface 添加到 pod，并设置 interface 属性
    // Set interface attributes for the new port
    epErr = setIfAttrs(pid, ep.PortName, ep.IPAddress, ep.IPv6Address, pInfo.IntfName)
    if epErr != nil {
        log.Errorf("Error setting interface attributes. Err: %v", epErr)
        setErrorResp(&resp, "Error setting interface attributes", epErr)
        return resp, epErr
    }

    //TODO: Host access needs to be enabled for IPv6
    // if Gateway is not specified on the nw, use the host gateway
    gwIntf := pInfo.IntfName
    gw := ep.Gateway
    if gw == "" {
        hostIf := netutils.GetHostIntfName(ep.PortName)
        hostIP, err := netPlugin.CreateHostAccPort(hostIf, ep.IPAddress)
        if err != nil {
            log.Errorf("Error setting host access. Err: %v", err)
        } else {
            err = setIfAttrs(pid, hostIf, hostIP, "", "host1")
            if err != nil {
                log.Errorf("Move to pid %d failed", pid)
            } else {
                gw, err = netutils.HostIPToGateway(hostIP)
                if err != nil {
                    log.Errorf("Error getting host GW ip: %s, err: %v", hostIP, err)
                } else {
                    gwIntf = "host1"
                    // make sure service subnet points to eth0
                    svcSubnet := contivK8Config.SvcSubnet
                    addStaticRoute(pid, svcSubnet, pInfo.IntfName)
                }
            }
        }

    }

    // 为 pod 设置默认路由
    // Set default gateway
    epErr = setDefGw(pid, gw, ep.IPv6Gateway, gwIntf)
    if epErr != nil {
        log.Errorf("Error setting default gateway. Err: %v", epErr)
        setErrorResp(&resp, "Error setting default gateway", epErr)
        return resp, epErr
    }

    resp.Result = 0
    resp.IPAddress = ep.IPAddress

    if ep.IPv6Address != "" {
        resp.IPv6Address = ep.IPv6Address
    }

    resp.EndpointID = pInfo.InfraContainerID

    return resp, nil
}

### 获取 pod label 信息，并构建 contiv endpointSpec

**mgmtfn/k8splugin/driver.go**

// getEPSpec gets the EP spec using the pod attributes
func getEPSpec(pInfo *cniapi.CNIPodAttr) (*epSpec, error) {
    resp := epSpec{}

    // Get labels from the kube api server
    epg, err := kubeAPIClient.GetPodLabel(pInfo.K8sNameSpace, pInfo.Name,
        "io.contiv.net-group")
    if err != nil {
        log.Errorf("Error getting epg. Err: %v", err)
        return &resp, err
    }

    // Safe to ignore the error return for subsequent invocations of GetPodLabel
    netw, _ := kubeAPIClient.GetPodLabel(pInfo.K8sNameSpace, pInfo.Name,
        "io.contiv.network")
    tenant, _ := kubeAPIClient.GetPodLabel(pInfo.K8sNameSpace, pInfo.Name,
        "io.contiv.tenant")
    log.Infof("labels is %s/%s/%s for pod %s\n", tenant, netw, epg, pInfo.Name)
    resp.Tenant = tenant
    resp.Network = netw
    resp.Group = epg
    resp.EndpointID = pInfo.InfraContainerID
    resp.Name = pInfo.Name

    return &resp, nil
}

### 创建 contiv endpoint

1. 向 netmaster 发送请求创建 contiv endpoint，state driver 中新增 contiv endpoint
2. netplugin 通过 network drive 创建 contiv endpoint，network drive 会创建相应的 interface，设置 burst、bandwidth 等参数
3. 从 state driver 中获取 pod ip、网关信息，封装成 epSpec 返回

**mgmtfn/k8splugin/driver.go**

// createEP creates the specified EP in contiv
func createEP(req *epSpec) (*epAttr, error) {

    // if the ep already exists, treat as error for now.
    netID := req.Network + "." + req.Tenant
    // 从 state drive 里面试图获取 enpoint 信息，如果已经存在则返回
    ep, err := utils.GetEndpoint(netID + "-" + req.EndpointID)
    if err == nil {
        return nil, fmt.Errorf("the EP %s already exists", req.EndpointID)
    }

    // Build endpoint request
    mreq := master.CreateEndpointRequest{
        TenantName:   req.Tenant,
        NetworkName:  req.Network,
        // 注意，contiv service 为 endpoint group name
        ServiceName:  req.Group,
        EndpointID:   req.EndpointID,
        EPCommonName: req.Name,
        ConfigEP: intent.ConfigEP{
            Container:   req.EndpointID,
            Host:        pluginHost,
            ServiceName: req.Group,
        },
    }

    // 向 netmaster 发送请求创建 contiv endpoint
    var mresp master.CreateEndpointResponse
    err = cluster.MasterPostReq("/plugin/createEndpoint", &mreq, &mresp)
    if err != nil {
        epCleanUp(req)
        return nil, err
    }

    // this response should contain IPv6 if the underlying network is configured with IPv6
    log.Infof("Got endpoint create resp from master: %+v", mresp)

    // netplugin 通过 network driver 创建 contiv endpoint
    // 在 ovs switch 上创建 port，并设置 port 的 burst、bandwidth 等属性
    // Ask netplugin to create the endpoint
    err = netPlugin.CreateEndpoint(netID + "-" + req.EndpointID)
    if err != nil {
        log.Errorf("Endpoint creation failed. Error: %s", err)
        epCleanUp(req)
        return nil, err
    }

    // 从 state driver 中获取 contiv endpoint 信息
    ep, err = utils.GetEndpoint(netID + "-" + req.EndpointID)
    if err != nil {
        epCleanUp(req)
        return nil, err
    }

    log.Debug(ep)
    // need to get the subnetlen from nw state.
    nw, err := utils.GetNetwork(netID)
    if err != nil {
        epCleanUp(req)
        return nil, err
    }

    epResponse := epAttr{}
    epResponse.PortName = ep.PortName
    epResponse.IPAddress = ep.IPAddress + "/" + strconv.Itoa(int(nw.SubnetLen))
    epResponse.Gateway = nw.Gateway

    if ep.IPv6Address != "" {
        epResponse.IPv6Address = ep.IPv6Address + "/" + strconv.Itoa(int(nw.IPv6SubnetLen))
        epResponse.IPv6Gateway = nw.IPv6Gateway
    }

    return &epResponse, nil
}

### network driver 创建 contiv endpoint

**netplugin/plugin/netplugin.go**

// CreateEndpoint creates an endpoint for a given ID.
func (p *NetPlugin) CreateEndpoint(id string) error {
    p.Lock()
    defer p.Unlock()
    return p.NetworkDriver.CreateEndpoint(id)
}

**drivers/ovsd/ovsdriver.go**

// CreateEndpoint creates an endpoint by named identifier
func (d *OvsDriver) CreateEndpoint(id string) error {
    var (
        err          error
        intfName     string
        epgKey       string
        epgBandwidth int64
        dscp         int
    )

    cfgEp := &mastercfg.CfgEndpointState{}
    cfgEp.StateDriver = d.oper.StateDriver
    err = cfgEp.Read(id)
    if err != nil {
        return err
    }

    // Get the nw config.
    cfgNw := mastercfg.CfgNetworkState{}
    cfgNw.StateDriver = d.oper.StateDriver
    err = cfgNw.Read(cfgEp.NetID)
    if err != nil {
        log.Errorf("Unable to get network %s. Err: %v", cfgEp.NetID, err)
        return err
    }

    pktTagType := cfgNw.PktTagType
    pktTag := cfgNw.PktTag
    cfgEpGroup := &mastercfg.EndpointGroupState{}
    // Read pkt tags from endpoint group if available
    if cfgEp.EndpointGroupKey != "" {
        cfgEpGroup.StateDriver = d.oper.StateDriver

        err = cfgEpGroup.Read(cfgEp.EndpointGroupKey)
        if err == nil {
            log.Debugf("pktTag: %v ", cfgEpGroup.PktTag)
            pktTagType = cfgEpGroup.PktTagType
            pktTag = cfgEpGroup.PktTag
            epgKey = cfgEp.EndpointGroupKey
            dscp = cfgEpGroup.DSCP
            if cfgEpGroup.Bandwidth != "" {
                epgBandwidth = netutils.ConvertBandwidth(cfgEpGroup.Bandwidth)
            }

        } else if core.ErrIfKeyExists(err) == nil {
            log.Infof("EPG %s not found: %v. will use network based tag ", cfgEp.EndpointGroupKey, err)
        } else {
            return err
        }
    }

    // Find the switch based on network type
    var sw *OvsSwitch
    if pktTagType == "vxlan" {
        sw = d.switchDb["vxlan"]
    } else {
        sw = d.switchDb["vlan"]
    }

    // Skip Veth pair creation for infra nw endpoints
    skipVethPair := (cfgNw.NwType == "infra")

    operEp := &drivers.OperEndpointState{}
    operEp.StateDriver = d.oper.StateDriver
    err = operEp.Read(id)
    if core.ErrIfKeyExists(err) != nil {
        return err
    } else if err == nil {
        // check if oper state matches cfg state. In case of mismatch cleanup
        // up the EP and continue add new one. In case of match just return.
        if operEp.Matches(cfgEp) {
            log.Printf("Found matching oper state for ep %s, noop", id)

            // Ask the switch to update the port
            err = sw.UpdatePort(operEp.PortName, cfgEp, pktTag, cfgNw.PktTag, dscp, skipVethPair)
            if err != nil {
                log.Errorf("Error creating port %s. Err: %v", intfName, err)
                return err
            }

            return nil
        }
        log.Printf("Found mismatching oper state for Ep, cleaning it. Config: %+v, Oper: %+v",
            cfgEp, operEp)
        d.DeleteEndpoint(operEp.ID)
    }

    if cfgNw.NwType == "infra" {
        // For infra nw, port name is network name
        intfName = cfgNw.NetworkName
    } else {
        // Get the interface name to use
        intfName, err = d.getIntfName()
        if err != nil {
            return err
        }
    }

    // Get OVS port name
    ovsPortName := getOvsPortName(intfName, skipVethPair)

    // 在 ovs switch 上创建 port，并设置 port 的 burst、bandwidth 等属性
    // Ask the switch to create the port
    err = sw.CreatePort(intfName, cfgEp, pktTag, cfgNw.PktTag, cfgEpGroup.Burst, dscp, skipVethPair, epgBandwidth)
    if err != nil {
        log.Errorf("Error creating port %s. Err: %v", intfName, err)
        return err
    }

    // save local endpoint info
    d.oper.localEpInfoMutex.Lock()
    d.oper.LocalEpInfo[id] = &EpInfo{
        Ovsportname: ovsPortName,
        EpgKey:      epgKey,
        BridgeType:  pktTagType,
    }
    d.oper.localEpInfoMutex.Unlock()
    err = d.oper.Write()
    if err != nil {
        return err
    }
    // Save the oper state
    operEp = &drivers.OperEndpointState{
        NetID:       cfgEp.NetID,
        EndpointID:  cfgEp.EndpointID,
        ServiceName: cfgEp.ServiceName,
        IPAddress:   cfgEp.IPAddress,
        IPv6Address: cfgEp.IPv6Address,
        MacAddress:  cfgEp.MacAddress,
        IntfName:    cfgEp.IntfName,
        PortName:    intfName,
        HomingHost:  cfgEp.HomingHost,
        VtepIP:      cfgEp.VtepIP}
    operEp.StateDriver = d.oper.StateDriver
    operEp.ID = id
    err = operEp.Write()
    if err != nil {
        return err
    }

    defer func() {
        if err != nil {
            operEp.Clear()
        }
    }()
    return nil
}

### 将 interface 添加到 pod，并设置 interface 属性

1. interface 移动到 pod network namespace
2. interface 重命名
3. 设置 interface ip 地址
4. set interface up

**mgmtfn/k8splugin/driver.go**

// setIfAttrs sets the required attributes for the container interface
func setIfAttrs(pid int, ifname, cidr, cidr6, newname string) error {
    nsenterPath, err := osexec.LookPath("nsenter")
    if err != nil {
        return err
    }
    // LookPath searches for an executable binary named file in the
    // directories named by the PATH environment variable.
    ipPath, err := osexec.LookPath("ip")
    if err != nil {
        return err
    }

    // LinkByName finds a link by name and returns a pointer to the object
    // find the link
    link, err := getLink(ifname)
    if err != nil {
        log.Errorf("unable to find link %q. Error %q", ifname, err)
        return err
    }

    // 将 interface move 到 pod 的 network namespace
    // LinkSetNsPid puts the device into a new network namespace. 
    // The pid must be a pid of a running process. 
    // Equivalent to: `ip link set $link netns $pid`
    // move to the desired netns
    err = netlink.LinkSetNsPid(link, pid)
    if err != nil {
        log.Errorf("unable to move interface %s to pid %d. Error: %s",
            ifname, pid, err)
        return err
    }

    // rename to the desired ifname
    nsPid := fmt.Sprintf("%d", pid)
    rename, err := osexec.Command(nsenterPath, "-t", nsPid, "-n", "-F", "--", ipPath, "link",
        "set", "dev", ifname, "name", newname).CombinedOutput()
    if err != nil {
        log.Errorf("unable to rename interface %s to %s. Error: %s",
            ifname, newname, err)
        return nil
    }
    log.Infof("Output from rename: %v", rename)

    // 设置 interface ipv4 地址
    // set the ip address
    assignIP, err := osexec.Command(nsenterPath, "-t", nsPid, "-n", "-F", "--", ipPath,
        "address", "add", cidr, "dev", newname).CombinedOutput()

    if err != nil {
        log.Errorf("unable to assign ip %s to %s. Error: %s",
            cidr, newname, err)
        return nil
    }
    log.Infof("Output from ip assign: %v", assignIP)

    if cidr6 != "" {
        out, err := osexec.Command(nsenterPath, "-t", nsPid, "-n", "-F", "--", ipPath,
            "-6", "address", "add", cidr6, "dev", newname).CombinedOutput()
        if err != nil {
            log.Errorf("unable to assign IPv6 %s to %s. Error: %s",
                cidr6, newname, err)
            return nil
        }
        log.Infof("Output of IPv6 assign: %v", out)
    }

    // Finally, mark the link up
    bringUp, err := osexec.Command(nsenterPath, "-t", nsPid, "-n", "-F", "--", ipPath,
        "link", "set", "dev", newname, "up").CombinedOutput()

    if err != nil {
        log.Errorf("unable to assign ip %s to %s. Error: %s",
            cidr, newname, err)
        return nil
    }
    log.Debugf("Output from ip assign: %v", bringUp)
    return nil

}

### 为 pod 设置默认路由

**mgmtfn/k8splugin/driver.go**

// setDefGw sets the default gateway for the container namespace
func setDefGw(pid int, gw, gw6, intfName string) error {
    nsenterPath, err := osexec.LookPath("nsenter")
    if err != nil {
        return err
    }
    routePath, err := osexec.LookPath("route")
    if err != nil {
        return err
    }
    // set default gw
    nsPid := fmt.Sprintf("%d", pid)
    out, err := osexec.Command(nsenterPath, "-t", nsPid, "-n", "-F", "--", routePath, "add",
        "default", "gw", gw, intfName).CombinedOutput()
    if err != nil {
        log.Errorf("unable to set default gw %s. Error: %s - %s", gw, err, out)
        return nil
    }

    if gw6 != "" {
        out, err := osexec.Command(nsenterPath, "-t", nsPid, "-n", "-F", "--", routePath,
            "-6", "add", "default", "gw", gw6, intfName).CombinedOutput()
        if err != nil {
            log.Errorf("unable to set default IPv6 gateway %s. Error: %s - %s", gw6, err, out)
            return nil
        }
    }

    return nil
}


## 将 pod 从 contiv 网络删除

**mgmtfn/k8splugin/driver.go**

// deletePod is the handler for pod deletes
func deletePod(w http.ResponseWriter, r *http.Request, vars map[string]string) (interface{}, error) {

    resp := cniapi.RspAddPod{}

    logEvent("del pod")

    content, err := ioutil.ReadAll(r.Body)
    if err != nil {
        log.Errorf("Failed to read request: %v", err)
        return resp, err
    }

    pInfo := cniapi.CNIPodAttr{}
    if err := json.Unmarshal(content, &pInfo); err != nil {
        return resp, err
    }

    // Get labels from the kube api server
    epReq, err := getEPSpec(&pInfo)
    if err != nil {
        log.Errorf("Error getting labels. Err: %v", err)
        setErrorResp(&resp, "Error getting labels", err)
        return resp, err
    }

    // 通过 network driver 删除 host access port
    netPlugin.DeleteHostAccPort(epReq.EndpointID)
    if err = epCleanUp(epReq); err != nil {
        log.Errorf("failed to delete pod, error: %s", err)
    }
    resp.Result = 0
    resp.EndpointID = pInfo.InfraContainerID
    return resp, nil
}

### netplugin 删除 host access port

**netplugin/plugin/netplugin.go**

// DeleteHostAccPort creates a host access port
func (p *NetPlugin) DeleteHostAccPort(portName string) error {
    p.Lock()
    defer p.Unlock()
    return p.NetworkDriver.DeleteHostAccPort(portName)
}

### ovs 删除 host access port

**drivers/ovsd/ovsdriver.go**

//DeleteHostAccPort deletes the access port
func (d *OvsDriver) DeleteHostAccPort(id string) error {
    sw, found := d.switchDb["host"]
    if found {
        operEp := &drivers.OperEndpointState{}
        operEp.StateDriver = d.oper.StateDriver
        err := operEp.Read(id)
        if err != nil {
            return err
        }
        d.HostProxy.DeleteLocalIP(operEp.IPAddress)
        portName := operEp.PortName
        intfName := netutils.GetHostIntfName(portName)
        return sw.DelHostPort(intfName, false)
    }

    return errors.New("host bridge not found")
}
