<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [<h1 id="1">1. kubelet 调用 cni 插件的流程</h1>](#h1-id11-kubelet-%E8%B0%83%E7%94%A8-cni-%E6%8F%92%E4%BB%B6%E7%9A%84%E6%B5%81%E7%A8%8Bh1)
- [<h1 id="2">2. Pod watch event example</h1>](#h1-id22-pod-watch-event-exampleh1)
- [<h1 id="3">3. kuryr-k8s-contorller 添加的 pod annotation</h1>](#h1-id33-kuryr-k8s-contorller-%E6%B7%BB%E5%8A%A0%E7%9A%84-pod-annotationh1)
- [<h1 id="4">4. kuryr-cni</h1>](#h1-id44-kuryr-cnih1)
  - [<h2 id="4.1">4.1. kuryr-cni 可执行文件</h2>](#h2-id4141-kuryr-cni-%E5%8F%AF%E6%89%A7%E8%A1%8C%E6%96%87%E4%BB%B6h2)
  - [<h2 id="4.2">4.2. kuryr-kubernetes/cni/main.py</h2>](#h2-id4242-kuryr-kubernetescnimainpyh2)
  - [<h2 id="4.3">4.3. CNIRunner</h2>](#h2-id4343-cnirunnerh2)
  - [<h2 id="4.4">4.4. K8sCNIPlugin</h2>](#h2-id4444-k8scnipluginh2)
  - [<h2 id="4.5">4.5. Watcher</h2>](#h2-id4545-watcherh2)
  - [<h2 id="4.6">4.6. CNIPipeline</h2>](#h2-id4646-cnipipelineh2)
  - [<h2 id="4.7">4.7. Dispatcher</h2>](#h2-id4747-dispatcherh2)
  - [<h2 id="4.8">4.8. AddHandler</h2>](#h2-id4848-addhandlerh2)
    - [<h3 id="4.8.1">4.8.1. openstack/os-vif/os_vif/__init__.py</h3>](#h3-id481481-openstackos-vifos_vif__init__pyh3)
    - [<h3 id="4.8.2">4.8.2. VIFOpenVSwitchDriver</h3>](#h3-id482482-vifopenvswitchdriverh3)
      - [<h4 id="4.8.2.1">4.8.2.1. BaseBridgeDriver</h4>](#h4-id48214821-basebridgedriverh4)
      - [<h4 id="4.8.2.2">4.8.2.2. create_ovs_vif_port</h4>](#h4-id48224822-create_ovs_vif_porth4)
    - [<h3 id="4.8.3">4.8.3. _configure_l3</h3>](#h3-id483483-_configure_l3h3)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

* [1. kubelet 调用 cni 插件的流程](#1)
* [2. Pod watch event example](#2)
* [3. kuryr-k8s-contorller 添加的 pod annotation](#3)
* [4. kuryr-cni](#4)
    * [4.1. kuryr-cni 可执行文件](#4.1)
    * [4.2. kuryr-kubernetes/cni/main.py](#4.2)
    * [4.3. CNIRunner](#4.3)
    * [4.4. K8sCNIPlugin](#4.4)
    * [4.5. Watcher](#4.5)
    * [4.6. CNIPipeline](#4.6)
    * [4.7. Dispatcher](#4.7)
    * [4.8. AddHandler](#4.8)
        * [4.8.1. openstack/os-vif/os_vif/__init__.py](#4.8.1)
        * [4.8.2. VIFOpenVSwitchDriver](#4.8.2)
            * [4.8.2.1. BaseBridgeDriver](#4.8.2.1)
            * [4.8.2.2. create_ovs_vif_port](#4.8.2.2)
        * [4.8.3. _configure_l3](#4.8.3)

# <h1 id="1">1. kubelet 调用 cni 插件的流程</h1>

如果 `kubelet` 启动时配置的网络插件为 `cni`: `--network-plugin=cni`, 则 `kubelet` 通过 `cniNetworkPlugin` 去调用 `cni` 可执行文件.

创建 `pod`: `SetUpPod() -> addToNetwork()`.
删除 `pod`: `TearDownPod()` -> `deleteFromNetwork()`.

```
// pkg/kubelet/network/network.go
// TODO: Consider making this value configurable.
const DefaultInterfaceName = "eth0"

// pkg/kubelet/network/cni/cni.go
func (plugin *cniNetworkPlugin) SetUpPod(namespace string, name string, id kubecontainer.ContainerID) error {
    if err := plugin.checkInitialized(); err != nil {
        return err
    }
    netnsPath, err := plugin.host.GetNetNS(id.ID)
    if err != nil {
        return fmt.Errorf("CNI failed to retrieve network namespace path: %v", err)
    }

    _, err = plugin.loNetwork.addToNetwork(name, namespace, id, netnsPath)
    if err != nil {
        glog.Errorf("Error while adding to cni lo network: %s", err)
        return err
    }

    _, err = plugin.getDefaultNetwork().addToNetwork(name, namespace, id, netnsPath)
    if err != nil {
        glog.Errorf("Error while adding to cni network: %s", err)
        return err
    }

    return err
}

func (network *cniNetwork) addToNetwork(podName string, podNamespace string, podInfraContainerID kubecontainer.ContainerID, podNetnsPath string) (*cnitypes.Result, error) {
    rt, err := buildCNIRuntimeConf(podName, podNamespace, podInfraContainerID, podNetnsPath)
    if err != nil {
        glog.Errorf("Error adding network: %v", err)
        return nil, err
    }

    netconf, cninet := network.NetworkConfig, network.CNIConfig
    glog.V(4).Infof("About to run with conf.Network.Type=%v", netconf.Network.Type)
    res, err := cninet.AddNetwork(netconf, rt)
    if err != nil {
        glog.Errorf("Error adding network: %v", err)
        return nil, err
    }

    return res, nil
}

func (plugin *cniNetworkPlugin) TearDownPod(namespace string, name string, id kubecontainer.ContainerID) error {
    if err := plugin.checkInitialized(); err != nil {
        return err
    }
    netnsPath, err := plugin.host.GetNetNS(id.ID)
    if err != nil {
        return fmt.Errorf("CNI failed to retrieve network namespace path: %v", err)
    }

    return plugin.getDefaultNetwork().deleteFromNetwork(name, namespace, id, netnsPath)
}

func (network *cniNetwork) deleteFromNetwork(podName string, podNamespace string, podInfraContainerID kubecontainer.ContainerID, podNetnsPath string) error {
    rt, err := buildCNIRuntimeConf(podName, podNamespace, podInfraContainerID, podNetnsPath)
    if err != nil {
        glog.Errorf("Error deleting network: %v", err)
        return err
    }

    netconf, cninet := network.NetworkConfig, network.CNIConfig
    glog.V(4).Infof("About to run with conf.Network.Type=%v", netconf.Network.Type)
    err = cninet.DelNetwork(netconf, rt)
    if err != nil {
        glog.Errorf("Error deleting network: %v", err)
        return err
    }
    return nil
}

func buildCNIRuntimeConf(podName string, podNs string, podInfraContainerID kubecontainer.ContainerID, podNetnsPath string) (*libcni.RuntimeConf, error) {
    glog.V(4).Infof("Got netns path %v", podNetnsPath)
    glog.V(4).Infof("Using netns path %v", podNs)

    rt := &libcni.RuntimeConf{
        ContainerID: podInfraContainerID.ID,
        NetNS:       podNetnsPath,
        IfName:      network.DefaultInterfaceName,
        Args: [][2]string{
            {"IgnoreUnknown", "1"},
            {"K8S_POD_NAMESPACE", podNs},
            {"K8S_POD_NAME", podName},
            {"K8S_POD_INFRA_CONTAINER_ID", podInfraContainerID.ID},
        },
    }

    return rt, nil
}
```

`AddNetwork()` 和 `DelNetwork()` 都是 `containernetworking/cni` 库函数代码:

```
// github.com/containernetworking/cni/libcni/api.go
func (c *CNIConfig) AddNetwork(net *NetworkConfig, rt *RuntimeConf) (*types.Result, error) {
    pluginPath, err := invoke.FindInPath(net.Network.Type, c.Path)
    if err != nil {
        return nil, err
    }

    return invoke.ExecPluginWithResult(pluginPath, net.Bytes, c.args("ADD", rt))
}

func (c *CNIConfig) DelNetwork(net *NetworkConfig, rt *RuntimeConf) error {
    pluginPath, err := invoke.FindInPath(net.Network.Type, c.Path)
    if err != nil {
        return err
    }

    net, err = injectRuntimeConfig(net, rt)
    if err != nil {
        return err
    }

    return invoke.ExecPluginWithoutResult(pluginPath, net.Bytes, c.args("DEL", rt))
}

func (c *CNIConfig) args(action string, rt *RuntimeConf) *invoke.Args {
    return &invoke.Args{
        Command:     action,
        ContainerID: rt.ContainerID,
        NetNS:       rt.NetNS,
        //
        // PluginArgs 是传递给 cni 可执行文件的额外参数, 用户可以自定义
        // 这里 kubelet 其实传递的是:
        //             Args: [][2]string{
        //                 {"IgnoreUnknown", "1"},
        //                 {"K8S_POD_NAMESPACE", podNs},
        //                 {"K8S_POD_NAME", podName},
        //                 {"K8S_POD_INFRA_CONTAINER_ID", podInfraContainerID.ID},
        //            },
        //
        PluginArgs:  rt.Args,
        IfName:      rt.IfName,
        Path:        strings.Join(c.Path, ":"),
    }
}

// github.com/containernetworking/cni/pkg/invoke/exec.go
func ExecPluginWithResult(pluginPath string, netconf []byte, args CNIArgs) (*types.Result, error) {
    stdoutBytes, err := execPlugin(pluginPath, netconf, args)
    if err != nil {
        return nil, err
    }

    res := &types.Result{}
    err = json.Unmarshal(stdoutBytes, res)
    return res, err
}

func ExecPluginWithoutResult(pluginPath string, netconf []byte, args CNIArgs) error {
    _, err := execPlugin(pluginPath, netconf, args)
    return err
}

func execPlugin(pluginPath string, netconf []byte, args CNIArgs) ([]byte, error) {
    stdout := &bytes.Buffer{}

    // plugin 所需的相关参数实际上是通过 Env 传递的
    c := exec.Cmd{
        Env:    args.AsEnv(),
        Path:   pluginPath,
        Args:   []string{pluginPath},
        Stdin:  bytes.NewBuffer(netconf),
        Stdout: stdout,
        Stderr: os.Stderr,
    }
    if err := c.Run(); err != nil {
        return nil, pluginErr(err, stdout.Bytes())
    }

    return stdout.Bytes(), nil
}

// github.com/containernetworking/cni/pkg/invoke/args.go
func (args *Args) AsEnv() []string {
    env := os.Environ()
    pluginArgsStr := args.PluginArgsStr
    if pluginArgsStr == "" {
        pluginArgsStr = stringify(args.PluginArgs)
    }

    env = append(env,
        "CNI_COMMAND="+args.Command,
        "CNI_CONTAINERID="+args.ContainerID,
        "CNI_NETNS="+args.NetNS,
        "CNI_ARGS="+pluginArgsStr,
        "CNI_IFNAME="+args.IfName,
        "CNI_PATH="+args.Path)
    return env
}
```

# <h1 id="2">2. Pod watch event example</h1>

```json
{
    "type":"ADDED",
    "object": {
        "kind":"Pod",
        "apiVersion":"v1",
        "metadata": {
            "name":"nginx-p8lbx",
            "generateName":"nginx-",
            "namespace":"default",
            "selfLink":"/api/v1/namespaces/default/pods/nginx-p8lbx",
            "uid":"9693c563-8966-11e7-a2a1-ac1f6b1274fa",
            "resourceVersion":"929758",
            "creationTimestamp":"2017-08-25T07:25:36Z",
            "deletionTimestamp":"2017-08-31T01:47:07Z",
            "deletionGracePeriodSeconds":30,
            "labels": { "app":"nginx" },
            "annotations": {
                "kubernetes.io/created-by": "{
                    \"kind\":\"SerializedReference\",
                    \"apiVersion\":\"v1\",
                    \"reference\": {
                        \"kind\":\"ReplicationController\",
                        \"namespace\":\"default\",
                        \"name\":\"nginx\",
                        \"uid\":\"63ce2552-88b2-11e7-a2a1-ac1f6b1274fa\",
                        \"apiVersion\":\"v1\",
                        \"resourceVersion\":\"288364\"
                    }
                }\n"
            },
            "ownerReferences":[{
                "apiVersion":"v1",
                "kind":"ReplicationController",
                "name":"nginx",
                "uid":"63ce2552-88b2-11e7-a2a1-ac1f6b1274fa",
                "controller":true,
                "blockOwnerDeletion":true
            }]
        },
        "spec": {
            "volumes":[{
                "name":"default-token-wpf02",
                "secret":{
                    "secretName":"default-token-wpf02",
                    "defaultMode":420
                }
            }],
            "containers":[{
                "name":"nginx",
                "image":"nginx:net.tools",
                "ports":[{
                    "containerPort":80,
                    "protocol":"TCP"
                }],
                "resources":{},
                "volumeMounts":[{
                    "name":"default-token-wpf02",
                    "readOnly":true,
                    "mountPath":"/var/run/secrets/kubernetes.io/serviceaccount"
                }],
                "terminationMessagePath":"/dev/termination-log",
                "terminationMessagePolicy":"File",
                "imagePullPolicy":"IfNotPresent"
            }],
            "restartPolicy":"Always",
            "terminationGracePeriodSeconds":30,
            "dnsPolicy":"ClusterFirst",
            "serviceAccountName":"default",
            "serviceAccount":"default",
            "nodeName":"computer2",
            "securityContext":{},
            "schedulerName":"default-scheduler"
        },
        "status":{
            "phase":"Running",
            "conditions":[{
                "type":"Initialized",
                "status":"True",
                "lastProbeTime":null,
                "lastTransitionTime":"2017-08-25T07:25:36Z"
            },
            {
                "type":"Ready",
                "status":"True",
                "lastProbeTime":null,
                "lastTransitionTime":"2017-08-25T07:26:03Z"
            },
            {
                "type":"PodScheduled",
                "status":"True",
                "lastProbeTime":null,
                "lastTransitionTime":"2017-08-25T07:25:36Z"
            }],
            "hostIP":"192.168.16.21",
            "podIP":"10.10.1.8",
            "startTime":"2017-08-25T07:25:36Z",
            "containerStatuses":[{
                "name":"nginx",
                "state":{
                    "running":{"startedAt":"2017-08-25T07:25:51Z"}
                },
                "lastState":{},
                "ready":true,
                "restartCount":0,
                "image":"nginx:net.tools",
                "imageID":"docker://sha256:d200f748dac803fb4d0d9f7f323b703a8c5273aabb9709ad1bc817bc68fb327e",
                "containerID":"docker://5e311f7788aca834e45203cf14ac5710f8b2ea596e21410f535638aae7c39776"
            }],
            "qosClass":"BestEffort"
        }
    }
}
```

# <h1 id="3">3. kuryr-k8s-contorller 添加的 pod annotation</h1>

```json
"openstack.org/kuryr-vif": "{
    \"versioned_object.data\": {
        \"active\": true, 
        \"address\": \"fa:16:3e:29:cf:9e\", 
        \"bridge_name\": \"br-int\",
        \"has_traffic_filtering\": true, 
        \"id\": \"2faf4e00-fc66-4746-83b2-1e5782e2ae92\",
        \"network\": {
            \"versioned_object.data\": {
                \"bridge\": \"br-int\", 
                \"id\": \"2dc4b4eb-9313-4007-9286-46ca79e71304\",
                \"label\": \"kuryr\",
                \"mtu\": 1500, 
                \"multi_host\": false, 
                \"should_provide_bridge\": false, 
                \"should_provide_vlan\": false, 
                \"subnets\": {
                    \"versioned_object.data\": {
                        \"objects\": [{
                            \"versioned_object.data\": {
                                \"cidr\": \"10.10.0.0/16\",
                                \"dns\": [], 
                                \"gateway\": \"10.10.0.254\",
                                \"ips\": {
                                    \"versioned_object.data\": {
                                        \"objects\": [{
                                            \"versioned_object.data\": {\"address\": \"10.10.1.8\"}, 
                                            \"versioned_object.name\": \"FixedIP\", 
                                            \"versioned_object.namespace\": \"os_vif\", 
                                            \"versioned_object.version\": \"1.0\"
                                        }]
                                    }, 
                                    \"versioned_object.name\": \"FixedIPList\", 
                                    \"versioned_object.namespace\": \"os_vif\", 
                                    \"versioned_object.version\": \"1.0\"
                                }, 
                                \"routes\": {
                                    \"versioned_object.data\": {
                                        \"objects\": []
                                    }, 
                                    \"versioned_object.name\": \"RouteList\", 
                                    \"versioned_object.namespace\": \"os_vif\", 
                                    \"versioned_object.version\": \"1.0\"
                                }
                            }, 
                            \"versioned_object.name\": \"Subnet\", 
                            \"versioned_object.namespace\": \"os_vif\", 
                            \"versioned_object.version\": \"1.0\"
                        }]
                    }, 
                    \"versioned_object.name\": \"SubnetList\", 
                    \"versioned_object.namespace\": \"os_vif\", 
                    \"versioned_object.version\": \"1.0\"
                }
            }, 
            \"versioned_object.name\": \"Network\", 
            \"versioned_object.namespace\": \"os_vif\", 
            \"versioned_object.version\": \"1.1\"
        }, 
        \"plugin\": \"ovs\", 
        \"port_profile\": {
            \"versioned_object.data\": {
                \"interface_id\": \"2faf4e00-fc66-4746-83b2-1e5782e2ae92\"
            }, 
            \"versioned_object.name\": \"VIFPortProfileOpenVSwitch\", 
            \"versioned_object.namespace\": \"os_vif\", 
            \"versioned_object.version\": \"1.0\"
        }, 
        \"preserve_on_delete\": false, 
        \"vif_name\": \"tap2faf4e00-fc\"
    }, 
    \"versioned_object.name\": \"VIFOpenVSwitch\", 
    \"versioned_object.namespace\": \"os_vif\", 
    \"versioned_object.version\": \"1.0\"
}"
```

# <h1 id="4">4. kuryr-cni</h1>

`kuryr-cni` 通过 `apiserver` 去 `watch` 所关心的 `pod event`:

```
self._watcher.add(
    "%(base)s/namespaces/%(namespace)s/pods"
    "?fieldSelector=metadata.name=%(pod)s" % {
        'base': k_const.K8S_API_BASE,
        'namespace': params.args.K8S_POD_NAMESPACE,
        'pod': params.args.K8S_POD_NAME})
```

`watch` 到 `pod ADDED` 事件之后, 从 `watch event` 中获取该 `pod` 的 `openstack port` 信息, 然后创建 `veth pair` 和 `ovs port`, 根据 `port` 信息去配置 `veth pair`, `veth pair` 的一端添加到 `pod`, 一端添加到 `ovs br-int` 或者是连接到 `ovs br-int` 的 `linux bridge`.

## <h2 id="4.1">4.1. kuryr-cni 可执行文件</h2>

从 `kuryr-kubernetes/setup.cfg` 可以知道: `kuryr-cni` 其实就是 `kuryr-kubernetes/cmd/cni.py` 中的 `run()` 函数:

```
# setup.cfg
[entry_points]
console_scripts =
    kuryr-k8s-controller = kuryr_kubernetes.cmd.eventlet.controller:start
    kuryr-cni = kuryr_kubernetes.cmd.cni:run
```

`kuryr-kubernetes/cmd/cni.py` 内容如下:

```
from kuryr_kubernetes.cni import main


run = main.run

if __name__ == '__main__':
    run()
```

`kubelet` 调用 `$BIN_PATH/kuryr-cni args` 执行网络设置, 然后从 `stdout` 中获取返回值, 其中 `args` 是通过 `stdin` 传入.

## <h2 id="4.2">4.2. kuryr-kubernetes/cni/main.py</h2>

```
# kuryr-kubernetes/cni/main.py
def run():
    runner = cni_api.CNIRunner(K8sCNIPlugin())
    status = runner.run(os.environ, sys.stdin, sys.stdout)
```

`run()` 函数各个参数的含义，我们可以从另外一个 `repo: github.com/containernetworking/cni` 来看:

```
// github.com/containernetworking/cni/pkg/invoke/exec.go
func execPlugin(pluginPath string, netconf []byte, args CNIArgs) ([]byte, error) {
    stdout := &bytes.Buffer{}

// Kubelet will look for the CNI Executable File (for example: kuryr-cni) in a
// list of predefined directories. Once found, it will invoke the executable
// using the following environment variables for argument passing:
//
//    CNI_COMMAND: indicates the desired operation; ADD, DEL or VERSION.
//    CNI_CONTAINERID: Container ID
//    CNI_NETNS: Path to network namespace file
//    CNI_IFNAME: Interface name to set up; plugin must honor this interface
//        name or return an error
//    CNI_ARGS: Extra arguments passed in by the user at invocation time.
//        Alphanumeric key-value pairs separated by semicolons;
//        for example, "FOO=BAR;ABC=123"
//    CNI_PATH: List of paths to search for CNI plugin executables.
//        Paths are separated by an OS-specific list separator;
//        for example ':' on Linux and ';' on Windows
//
// Network configuration in JSON format is streamed to the plugin through
// stdin. This means it is not tied to a particular file on disk and can
// contain information which changes between invocations.

    c := exec.Cmd{
        Env:    args.AsEnv(),
        Path:   pluginPath,
        Args:   []string{pluginPath},
        Stdin:  bytes.NewBuffer(netconf),
        Stdout: stdout,
        Stderr: os.Stderr,
    }
    if err := c.Run(); err != nil {
        return nil, pluginErr(err, stdout.Bytes())
    }

    return stdout.Bytes(), nil
}

// github.com/containernetworking/cni/pkg/invoke/args.go
func (args *Args) AsEnv() []string {
    env := os.Environ()
    pluginArgsStr := args.PluginArgsStr
    if pluginArgsStr == "" {
        pluginArgsStr = stringify(args.PluginArgs)
    }

    env = append(env,
        "CNI_COMMAND="+args.Command,
        "CNI_CONTAINERID="+args.ContainerID,
        "CNI_NETNS="+args.NetNS,
        "CNI_ARGS="+pluginArgsStr,
        "CNI_IFNAME="+args.IfName,
        "CNI_PATH="+args.Path)
    return env
}
```

`kuryr-cni` 执行时, 参数传递由两部分组成, 一部分通过 `env` 环境变量传入, 这部分主要是 `cni` 插件执行 `ADD` 或者 `DEL` 函数时所需要的参数; 另一部分通过 `stdin` 传入, 这里主要是指 `kubelet` 使用的 `cni` 插件的配置文件(`json` 格式, 比如 `etc/cni/net.d/10-kuryr.conf`)的内容将以流的方式传入.

```
# cat etc/cni/net.d/10-kuryr.conf
{
  "cniVersion": "0.3.0",
  "name": "kuryr",
  "type": "kuryr-cni",
  "kuryr_conf": "/etc/kuryr/kuryr.conf",
  "debug": true
}
```

另外, `kubelet` 还会通过 `CNI_ARGS` 传递一些额外的参数:

```
// pkg/kubelet/network/cni/cni.go
{
    {"IgnoreUnknown", "1"},
    {"K8S_POD_NAMESPACE", podNs},
    {"K8S_POD_NAME", podName},
    {"K8S_POD_INFRA_CONTAINER_ID", podInfraContainerID.ID},
}
```

下面我们看 `CNIRunner` 类.

## <h2 id="4.3">4.3. CNIRunner</h2>

```
# kuryr_kubernetes/cni/api.py
class CNIRunner(object):

    def __init__(self, plugin):
        self._plugin = plugin

    def run(self, env, fin, fout):
        try:
            params = CNIParameters(env, jsonutils.load(fin))

            if params.CNI_COMMAND == 'ADD':
                vif = self._plugin.add(params)
                self._write_vif(fout, vif)
            elif params.CNI_COMMAND == 'DEL':
                self._plugin.delete(params)
            elif params.CNI_COMMAND == 'VERSION':
                self._write_version(fout)
            else:
                raise k_exc.CNIError(_("unknown CNI_COMMAND: %s")
                                     % params.CNI_COMMAND)
            return 0
        except Exception as ex:
            # LOG.exception
            self._write_exception(fout, str(ex))
            return 1

    def _write_vif(self, fout, vif):
        result = {}
        nameservers = []

        for subnet in vif.network.subnets.objects:
            nameservers.extend(subnet.dns)

            ip = subnet.ips.objects[0].address
            cni_ip = result.setdefault("ip%s" % ip.version, {})
            cni_ip['ip'] = "%s/%s" % (ip, subnet.cidr.prefixlen)

            if subnet.gateway:
                cni_ip['gateway'] = str(subnet.gateway)

            if subnet.routes.objects:
                cni_ip['routes'] = [
                    {'dst': str(route.cidr), 'gw': str(route.gateway)}
                    for route in subnet.routes.objects]

        if nameservers:
            result['dns'] = {'nameservers': nameservers}

        self._write_dict(fout, result)

    def _write_dict(self, fout, dct):
        output = {'cniVersion': self.VERSION}
        output.update(dct)
        LOG.debug("CNI output: %s", output)
        jsonutils.dump(output, fout, sort_keys=True)
```

当 `kubelet` 调用 `AddNetwork()` 函数时, 会调用 `kuryr-cni` 执行 `ADD` 命令, 成功执行之后将返回值 `vif` 对象输出到 `stdout`;

当 `kubelet` 调用 `DelNetwork()` 函数时, 会调用 `kuryr-cni` 执行 `DEL` 命令.

在这里, 真正执行这两个命令的主体是 `K8sCNIPlugin` 类的 `add()` 和 `delete()` 函数.

## <h2 id="4.4">4.4. K8sCNIPlugin</h2>

```
# kuryr_kubernetes/cni/main.py
class K8sCNIPlugin(cni_api.CNIPlugin):

    def add(self, params):
        self._setup(params)
        # 注册 consumer
        self._pipeline.register(h_cni.AddHandler(params, self._done))
        self._watcher.start()
        return self._vif

    def delete(self, params):
        self._setup(params)
        # 注册 consumer
        self._pipeline.register(h_cni.DelHandler(params, self._done))
        self._watcher.start()

    def _done(self, vif):
        self._vif = vif
        self._watcher.stop()

    def _setup(self, params):
        args = ['--config-file', params.config.kuryr_conf]

        try:
            if params.config.debug:
                args.append('-d')
        except AttributeError:
            pass

        # 解析命令行参数
        config.init(args)
        config.setup_logging()
        # github.com/openstack/os_vif/os_vif/__init__.py
        #
        # def initialize(reset=False):
        #     """
        #     Loads all os_vif plugins and initializes them with a dictionary of
        #     configuration options. These configuration options are passed as-is
        #     to the individual VIF plugins that are loaded via stevedore.
        #     :param reset: Recreate and load the VIF plugin extensions.
        #     """
        #     global _EXT_MANAGER
        #     if _EXT_MANAGER is None:
        #         os_vif.objects.register_all()
        # 
        #     if reset or (_EXT_MANAGER is None):
        #         _EXT_MANAGER = extension.ExtensionManager(namespace='os_vif',
        #                                             invoke_on_load=False)
        #         loaded_plugins = []
        #         for plugin_name in _EXT_MANAGER.names():
        #             cls = _EXT_MANAGER[plugin_name].plugin
        #             obj = cls.load(plugin_name)
        #             LOG.debug(("Loaded VIF plugin class '%(cls)s' "
        #                        "with name '%(plugin_name)s'"),
        #                       {'cls': cls, 'plugin_name': plugin_name})
        #             loaded_plugins.append(plugin_name)
        #             _EXT_MANAGER[plugin_name].obj = obj
        #         LOG.info("Loaded VIF plugins: %s", ", ".join(loaded_plugins))
        #
        #
        # stevedore 基于 setuptools entry point, 提供 python 应用程序管理插件的功能.
        # os_vif 正式利用 stevedore 加载多个 plugin.
        #
        # 我们看 github.com/openstack/kuryr-kubernetes/setup.cfg:
        #     [entry_points]
        #     os_vif =
        #         noop = kuryr_kubernetes.os_vif_plug_noop:NoOpPlugin
        #
        # 然后 github.com/openstack/os-vif/setup.cfg:
        #     [entry_points]
        #     os_vif =
        #         linux_bridge = vif_plug_linux_bridge.linux_bridge:LinuxBridgePlugin
        #         ovs = vif_plug_ovs.ovs:OvsPlugin
        #
        #
        os_vif.initialize()
        clients.setup_kubernetes_client()
        self._pipeline = h_cni.CNIPipeline()
        self._watcher = k_watcher.Watcher(self._pipeline)
        # watch pod metadata
        self._watcher.add(
            "%(base)s/namespaces/%(namespace)s/pods"
            "?fieldSelector=metadata.name=%(pod)s" % {
                'base': k_const.K8S_API_BASE,
                'namespace': params.args.K8S_POD_NAMESPACE,
                'pod': params.args.K8S_POD_NAME})
```

## <h2 id="4.5">4.5. Watcher</h2>

`Watcher` 对象负责 `watch` 指定的 `pod` 资源

```
# kuryr-kubernetes/kuryr-kubernetes/watcher.py
class Watcher(object):
    """Observes K8s resources' events using K8s '?watch=true' API.

    The `Watcher` maintains a list of K8s resources and manages the event
    processing loops for those resources. Event handling is delegated to the
    `callable` object passed as the `handler` initialization parameter that
    will be run for each K8s event observed by the `Watcher`.

    The `Watcher` can operate in two different modes based on the
    `thread_group` initialization parameter:

      - synchronous, when the event processing loops run on the same thread
        that called 'add' or 'start' methods

      - asynchronous, when each event processing loop runs on its own thread
        (`oslo_service.threadgroup.Thread`) from the `thread_group`

    When started, the `Watcher` will run the event processing loops for each
    of the K8s resources on the list. Adding a K8s resource to the running
    `Watcher` also ensures that the event processing loop for that resource is
    running.

    Stopping the `Watcher` or removing the specific K8s resource from the
    list will request the corresponding running event processing loops to
    stop gracefully, but will not interrupt any running `handler`. Forcibly
    stopping any 'stuck' `handler` is not supported by the `Watcher` and
    should be handled externally (e.g. by using `thread_group.stop(
    graceful=False)` for asynchronous `Watcher`).
    """

    def __init__(self, handler, thread_group=None):
        """Initializes a new Watcher instance.

        :param handler: a `callable` object to be invoked for each observed
                        K8s event with the event body as a single argument.
                        Calling `handler` should never raise any exceptions
                        other than `eventlet.greenlet.GreenletExit` caused by
                        `eventlet.greenthread.GreenThread.kill` when the
                        `Watcher` is operating in asynchronous mode.
        :param thread_group: an `oslo_service.threadgroup.ThreadGroup`
                             object used to run the event processing loops
                             asynchronously. If `thread_group` is not
                             specified, the `Watcher` will operate in a
                             synchronous mode.
        """
        self._client = clients.get_kubernetes_client()
        self._handler = handler
        self._thread_group = thread_group
        self._running = False

        self._resources = set()
        # self._watching[path] means: path is watching in default thread or another thread based on thread group
        self._watching = {}
        # self._idle[path] means: path is handling or not
        self._idle = {}

    def add(self, path):
        """Adds ths K8s resource to the Watcher.

        Adding a resource to a running `Watcher` also ensures that the event
        processing loop for that resource is running. This method could block
        for `Watcher`s operating in synchronous mode.

        :param path: K8s resource URL path
        """
        self._resources.add(path)
        if self._running and path not in self._watching:
            self._start_watch(path)

    def remove(self, path):
        """Removes the K8s resource from the Watcher.

        Also requests the corresponding event processing loop to stop if it
        is running.

        :param path: K8s resource URL path
        """
        self._resources.discard(path)
        if path in self._watching:
            self._stop_watch(path)

    def start(self):
        """Starts the Watcher.

        Also ensures that the event processing loops are running. This method
        could block for `Watcher`s operating in synchronous mode.
        """
        self._running = True
        for path in self._resources - set(self._watching):
            self._start_watch(path)

    def stop(self):
        """Stops the Watcher.

        Also requests all running event processing loops to stop.
        """
        self._running = False
        for path in list(self._watching):
            self._stop_watch(path)

    def _start_watch(self, path):
        tg = self._thread_group
        self._idle[path] = True
        if tg:
            self._watching[path] = tg.add_thread(self._watch, path)
        else:
            self._watching[path] = None
            self._watch(path)

    def _stop_watch(self, path):
        if self._idle.get(path):
            if self._thread_group:
                self._watching[path].stop()

    def _watch(self, path):
        try:
            LOG.info("Started watching '%s'", path)
            for event in self._client.watch(path):
                self._idle[path] = False
                self._handler(event)
                self._idle[path] = True
                if not (self._running and path in self._resources):
                    return
        finally:
            self._watching.pop(path)
            self._idle.pop(path)
            LOG.info("Stopped watching '%s'", path)
```

下面我们看看 `self._client.watch(path)` 的具体实现:

```
# kuryr-kubernetes/kuryr-kubernetes/k8s_client.py
class K8sClient(object):

    # 由于 yield 关键字, watch 变成一个生成器
    def watch(self, path):
        # Watch API 实际上一个标准的 HTTP GET 请求, 我们以 Pod 的 Watch API 为例
        #     HTTP Request
        #         GET /api/v1/watch/namespaces/{namespace}/pods
        #
        #       Path Parameters:
        #         namespace: object name and auth scope
        #
        #       Query Parameters:
        #         fieldSelector: A selector to restrict the list of returned
        #             objects by their fields. Defaults to everything.
        #         labelSelector: A selector to restrict the list of returned
        #             objects by their labels. Defaults to everything.
        #         pretty: If ‘true’, then the output is pretty printed.
        #         resourceVersion: When specified with a watch call, shows
        #             changes that occur after that particular version of a
        #             resource.
        #         timeoutSeconds: Timeout for the list/watch call.
        #         watch: Watch for changes to the described resources and
        #             return them as a stream of add, update, and remove
        #             notifications.
        params = {'watch': 'true'}
        url = self._base_url + path
        header = {}
        if self.token:
            header.update({'Authorization': 'Bearer %s' % self.token})

        # TODO(ivc): handle connection errors and retry on failure
        while True:
            with contextlib.closing(
                    requests.get(url, params=params, stream=True,
                                 cert=self.cert, verify=self.verify_server,
                                 headers=header)) as response:
                if not response.ok:
                    raise exc.K8sClientException(response.text)
                # refer to: kubernetes/pkg/apiserver/watch.go: ServeHTTP()
                # // Event represents a single event to a watched resource.
                # type Event struct {
                #     Type EventType
                # 
                #     // Object is:
                #     //  * If Type is Added or Modified: the new state of the object.
                #     //  * If Type is Deleted: the state of the object immediately before deletion.
                #     //  * If Type is Error: *api.Status is recommended; other types may make sense
                #     //    depending on context.
                #     Object runtime.Object
                # }
                for line in response.iter_lines(delimiter='\n'):
                    line = line.strip()
                    if line:
                        # jsonutils.loads() return a python dict
                        yield jsonutils.loads(line)
```

从 `Watcher` 类的 `_watch()` 函数可以知道, 当 `watch` 到 `event` 之后, 将由 `CNIPipeline` 类对象通过调用 `dispatcher` 将 `event` 指派到对应的 `consumer` 去处理.

```
# kuryr-kubernetes/kuryr-kubernetes/watcher.py
class Watcher(object):
    def _watch(self, path):
        try:
            LOG.info("Started watching '%s'", path)
            for event in self._client.watch(path):
                self._idle[path] = False
                self._handler(event)
                self._idle[path] = True
                if not (self._running and path in self._resources):
                    return
        finally:
            self._watching.pop(path)
            self._idle.pop(path)
            LOG.info("Stopped watching '%s'", path)
```

这里的 `_handler` 即是 `CNIPipeline` 类对象.

## <h2 id="4.6">4.6. CNIPipeline</h2>

```
# kuryr-kubernetes/kuryr-kubernetes/cni/handlers.py
class CNIPipeline(k_dis.EventPipeline):

    def _wrap_dispatcher(self, dispatcher):
        return dispatcher

    def _wrap_consumer(self, consumer):
        return consumer

# kuryr-kubernetes/kuryr-kubernetes/handlers/dispatch.py
@six.add_metaclass(abc.ABCMeta)
class EventPipeline(h_base.EventHandler):
    """Serves as an entry-point for event handling.

    Implementing subclasses should override `_wrap_dispatcher` and/or
    `_wrap_consumer` methods to sanitize the consumers passed to `register`
    (i.e. to satisfy the `Watcher` requirement that the event handler does
    not raise exceptions) and to add features like asynchronous event
    processing or retry-on-failure functionality.
    """

    def __init__(self):
        self._dispatcher = Dispatcher()
        self._handler = self._wrap_dispatcher(self._dispatcher)

    def register(self, consumer):
        """Adds handler to the registry.

        :param consumer: `EventConsumer`-type object
        """
        handler = self._wrap_consumer(consumer)
        for key_fn, key in consumer.consumes.items():
            self._dispatcher.register(key_fn, key, handler)

    def __call__(self, event):
        self._handler(event)

    @abc.abstractmethod
    def _wrap_dispatcher(self, dispatcher):
        raise NotImplementedError()

    @abc.abstractmethod
    def _wrap_consumer(self, consumer):
        raise NotImplementedError()

# kuryr-kubernetes/kuryr-kubernetes/handlers/base.py
@six.add_metaclass(abc.ABCMeta)
class EventHandler(object):
    """Base class for event handlers."""

    @abc.abstractmethod
    def __call__(self, event):
        """Handle the event."""
        raise NotImplementedError()

    def __str__(self):
        return self.__class__.__name__
```

`CNIPipeline` 的类继承关系如下:

`CNIPipeline <- EventPipeline <- EventHandler`

从 `EventPipeline` 类的初始化函数中可以看出真正的 `dispacher` 是 `Dispatcher` 类.

所以, `EventPipeline` 中 `__call__()` 函数调用的是 `Dispatcher` 类对象.

下面看看 `Dispatcher` 类.

## <h2 id="4.7">4.7. Dispatcher</h2>

```
# kuryr-kubernetes/kuryr-kubernetes/handlers/dispatch.py
class Dispatcher(h_base.EventHandler):
    """Dispatches events to registered handlers.

    Dispatcher serves as both multiplexer and filter for dispatching events
    to multiple registered handlers based on the event content and
    predicates provided during the handler registration.
    """

    def __init__(self):
        self._registry = {}

    def register(self, key_fn, key, handler):
        """Adds handler to the registry.

        `key_fn` and `key` constitute the `key_fn(event) == key` predicate
        that determines if the `handler` should be called for a given `event`.

        :param key_fn: function that will be called for each event to
                       determine the event `key`
        :param key: value to match against the result of `key_fn` function
                    that determines if the `handler` should be called for an
                    event
        :param handler: `callable` object that would be called if the
                        conditions specified by `key_fn` and `key` are met
        """
        # dict.setdefault(key, default=None)
        #   如果键不存在于字典中, 将会添加键并将值设为默认值
        #   返回值:
        #     如果字典中包含有给定键, 则返回该键对应的值, 否则返回为该键设置的值.
        #
        # example:
        #   key_fn: {
        #       Pod: [xx_podHandler, yy_podHandler],
        #       Endpoint: [xx_epHandler, yy_epHandler],
        #       Service: [xx_svcHandler, yy_svcHandler]
        # }
        key_group = self._registry.setdefault(key_fn, {})
        handlers = key_group.setdefault(key, [])
        handlers.append(handler)

    def __call__(self, event):
        handlers = set()

        for key_fn, key_group in self._registry.items():
            key = key_fn(event)
            # dict.get(key, default=None)
            #   函数返回指定键的值, 如果值不在字典中返回默认值
            handlers.update(key_group.get(key, ()))

        LOG.debug("%s handler(s) available", len(handlers))
        for handler in handlers:
            handler(event)
```

这里 `register()` 函数的调用流程如下:

```
K8sCNIPlugin: add(): self._pipeline.register(h_cni.AddHandler(params, self._done))
-->
CNIPipeline: register()
-->
EventPipeline: register()
-->
Dispatcher: register()
```

`Dispatcher` 的分发函数 `__call__()` 的原理如下:

- 首先通过 `key_fn` 获取 `event` 对应的 `key`
- 然后通过该 `key` 获取其对应的所有处理函数
- 让所有处理函数都对该 `event` 进行处理一遍

下面我们从 `AddHandler` 这个 `consumer` 去看看它的 `key_fn`, `key`, 和处理函数.

## <h2 id="4.8">4.8. AddHandler</h2>

```
# kuryr-kubernetes/kuryr_kubernetes/cni/handlers.py
class AddHandler(CNIHandlerBase):

    def __init__(self, cni, on_done):
        LOG.debug("AddHandler called with CNI env: %r", cni)
        super(AddHandler, self).__init__(cni, on_done)
        self._vif = None

    def on_vif(self, pod, vif):
        if not self._vif:
            self._vif = vif.obj_clone()
            self._vif.active = True
            b_base.connect(self._vif, self._get_inst(pod),
                           self._cni.CNI_IFNAME, self._cni.CNI_NETNS)

        if vif.active:
            self._callback(vif)

@six.add_metaclass(abc.ABCMeta)
class CNIHandlerBase(k8s_base.ResourceEventHandler):
    OBJECT_KIND = k_const.K8S_OBJ_POD

    def __init__(self, cni, on_done):
        self._cni = cni
        self._callback = on_done
        self._vif = None

    def on_present(self, pod):
        vif = self._get_vif(pod)

        if vif:
            self.on_vif(pod, vif)

    @abc.abstractmethod
    def on_vif(self, pod, vif):
        raise NotImplementedError()

    def _get_vif(self, pod):
        # TODO(ivc): same as VIFHandler._get_vif
        try:
            annotations = pod['metadata']['annotations']
            vif_annotation = annotations[k_const.K8S_ANNOTATION_VIF]
        except KeyError:
            return None
        vif_dict = jsonutils.loads(vif_annotation)
        vif = obj_vif.vif.VIFBase.obj_from_primitive(vif_dict)
        LOG.debug("Got VIF from annotation: %r", vif)
        return vif

    def _get_inst(self, pod):
        return obj_vif.instance_info.InstanceInfo(
            uuid=pod['metadata']['uid'], name=pod['metadata']['name'])

# kuryr-kubernetes/kuryr_kubernetes/handlers/k8s_base.py
class ResourceEventHandler(dispatch.EventConsumer):
    """Base class for K8s event handlers.

    Implementing classes should override the `OBJECT_KIND` attribute with a
    valid Kubernetes object type name (e.g. 'Pod' or 'Namespace'; see [1]
    for more details).

    Implementing classes are expected to override any or all of the
    `on_added`, `on_present`, `on_modified`, `on_deleted` methods that would
    be called depending on the type of the event (with K8s object as a single
    argument).

    [1] https://github.com/kubernetes/kubernetes/blob/release-1.4/docs/devel\
        /api-conventions.md#types-kinds
    """

    OBJECT_KIND = None

    @property
    def consumes(self):
        return {object_kind: self.OBJECT_KIND}

    # refer to: kubernetes/pkg/apiserver/watch.go: ServeHTTP()
    # // Event represents a single event to a watched resource.
    # type Event struct {
    #     Type EventType
    # 
    #     // Object is:
    #     //  * If Type is Added or Modified: the new state of the object.
    #     //  * If Type is Deleted: the state of the object immediately before deletion.
    #     //  * If Type is Error: *api.Status is recommended; other types may make sense
    #     //    depending on context.
    #     Object runtime.Object
    # }
    def __call__(self, event):
        event_type = event.get('type')
        obj = event.get('object')
        if 'MODIFIED' == event_type:
            self.on_modified(obj)
            self.on_present(obj)
        elif 'ADDED' == event_type:
            self.on_added(obj)
            self.on_present(obj)
        elif 'DELETED' == event_type:
            self.on_deleted(obj)

    def on_added(self, obj):
        pass

    def on_present(self, obj):
        pass

    def on_modified(self, obj):
        pass

    def on_deleted(self, obj):
        pass

# kuryr-kubernetes/kuryr-kubernetes/handlers/dispatch.py
@six.add_metaclass(abc.ABCMeta)
class EventConsumer(h_base.EventHandler):
    """Consumes events matching specified predicates.

    EventConsumer is an interface for all event handlers that are to be
    registered by the `EventPipeline`.
    """

    @abc.abstractproperty
    def consumes(self):
        """Predicates determining events supported by this handler.

        :return: `dict` object containing {key_fn: key} predicates to be
                 used by `Dispatcher.register`
        """
        raise NotImplementedError()
```

`AddHandler` 类的继承关系如下:

`AddHandler <- CNIHandlerBase <- ResourceEventHandler <- EventConsumer <- EventHandler`

所以 `AddHandler` 也属于一个 `EventConsumer`.

我们知道 `EventPipeline: register()` 函数完成了 `consumer` 注册:

```
# kuryr-kubernetes/kuryr-kubernetes/handlers/dispatch.py
@six.add_metaclass(abc.ABCMeta)
class EventPipeline(h_base.EventHandler):
    def register(self, consumer):
        """Adds handler to the registry.

        :param consumer: `EventConsumer`-type object
        """
        handler = self._wrap_consumer(consumer)
        for key_fn, key in consumer.consumes.items():
            self._dispatcher.register(key_fn, key, handler)
```

而 `consumer` 的 `key_fn`, `key`, 和处理函数的注册是通过 `Dispacher: register()` 函数完成的. 下面看看 `AddHandler` 和 `consumer.consumes.items()`.

通过 `AddHandler` 的继承关系我们知道, `AddHandler` 的 `consumes()` 是在 `ResourceEventHandler` 中实现的:

```
# kuryr-kubernetes/kuryr_kubernetes/handlers/k8s_base.py
class ResourceEventHandler(dispatch.EventConsumer):
    OBJECT_KIND = None

    @property
    def consumes(self):
        return {object_kind: self.OBJECT_KIND}
```

`ResourceEventHandler: consumes()` 函数返回的是一个字典, 该字典存储的是 `key_fn: key` 健值对, 字典中包含一个 `object_kind` 的 `key_fn` 和一个 `OBJECT_KIND` 的 `key`.

`object_kind` 的定义如下:

```
# kuryr-kubernetes/kuryr_kubernetes/handlers/k8s_base.py
def object_kind(event):
    try:
        return event['object']['kind']
    except KeyError:
        return None
```

而 `OBJECT_KIND` 的值是在 `CNIHandlerBase` 中定义的.

```
# kuryr-kubernetes/kuryr_kubernetes/cni/handlers.py
class CNIHandlerBase(k8s_base.ResourceEventHandler):
    OBJECT_KIND = k_const.K8S_OBJ_POD

# kuryr-kubernetes/kuryr_kubernetes/constants.py
K8S_OBJ_POD = 'Pod'
```

下面我们看 `AddHandler` 如何处理 `Event` 的. `AddHandler` 的处理逻辑是在 `ResourceEventHandler: __call__()` 函数中体现的:

```
# kuryr-kubernetes/kuryr_kubernetes/handlers/k8s_base.py
class ResourceEventHandler(dispatch.EventConsumer):
    # 此时的 event 是一个 dict
    def __call__(self, event):
        event_type = event.get('type')
        obj = event.get('object')
        if 'MODIFIED' == event_type:
            self.on_modified(obj)
            self.on_present(obj)
        elif 'ADDED' == event_type:
            self.on_added(obj)
            self.on_present(obj)
        elif 'DELETED' == event_type:
            self.on_deleted(obj)
```

从前面 `ResourceEventHandler` 类的分析来看, 不管是 `MODIFIED` 还是 `ADDED` 事件, 都只跟 `on_present()` 函数有关, `AddHandler` 的 `on_present()` 函数体现在 `CNIHandlerBase` 类中:

```
# kuryr-kubernetes/kuryr_kubernetes/cni/handlers.py
@six.add_metaclass(abc.ABCMeta)
class CNIHandlerBase(k8s_base.ResourceEventHandler):
    def on_present(self, pod):
        vif = self._get_vif(pod)

        if vif:
            self.on_vif(pod, vif)

    @abc.abstractmethod
    def on_vif(self, pod, vif):
        raise NotImplementedError()

    def _get_vif(self, pod):
        # TODO(ivc): same as VIFHandler._get_vif
        try:
            annotations = pod['metadata']['annotations']
            vif_annotation = annotations[k_const.K8S_ANNOTATION_VIF]
        except KeyError:
            return None
        vif_dict = jsonutils.loads(vif_annotation)
        # refer to openstack/oslo.versionedobjects/oslo_versionedobjects/base.py:VersionedObject
        vif = obj_vif.vif.VIFBase.obj_from_primitive(vif_dict)
        LOG.debug("Got VIF from annotation: %r", vif)
        return vif
```

首先通过 `pod annotation` 构建一个 `vif` 对象, 返回的 `vif` 的内容如下:

```
Got VIF from annotation: 
VIFOpenVSwitch(active=True,address=fa:16:3e:3f:95:b5,bridge_name='br-int',has_traffic_filtering=True,id=a77d35cf-31c0-4c04-ba9d-fed095bac91a,network=Network(2dc4b4eb-9313-4007-9286-46ca79e71304),plugin='ovs',port_profile=VIFPortProfileBase,preserve_on_delete=False,vif_name='tapa77d35cf-31')
```

然后执行 `on_vif()`. `AddHandler` 的 `on_vif()` 函数如下:

```
# kuryr-kubernetes/kuryr_kubernetes/cni/handlers.py
class AddHandler(CNIHandlerBase):
    def on_vif(self, pod, vif):
        if not self._vif:
            self._vif = vif.obj_clone()
            self._vif.active = True
            b_base.connect(self._vif, self._get_inst(pod),
                           self._cni.CNI_IFNAME, self._cni.CNI_NETNS)

        if vif.active:
            self._callback(vif)
```

我们继续看 `b_base.connect()` 函数:

```
# kuryr-kubernetes/kuryr_kubernetes/cni/binding/base.py
_BINDING_NAMESPACE = 'kuryr_kubernetes.cni.binding'
# ifname 为 pod interface name
def connect(vif, instance_info, ifname, netns=None):
    driver = _get_binding_driver(vif)
    # openstack/os-vif/os_vif/__init__.py:plug()
    os_vif.plug(vif, instance_info)
    # For example: VIFOpenVSwitchDriver
    driver.connect(vif, ifname, netns)
    # 为 pod 配置 ip, netmask, route, gateway
    _configure_l3(vif, ifname, netns)

# setup.cfg
#
# [entry_points]
# kuryr_kubernetes.cni.binding =
#     VIFBridge = kuryr_kubernetes.cni.binding.bridge:BridgeDriver
#     VIFOpenVSwitch = kuryr_kubernetes.cni.binding.bridge:VIFOpenVSwitchDriver
#     VIFVlanNested = kuryr_kubernetes.cni.binding.nested:VlanDriver
#     VIFMacvlanNested = kuryr_kubernetes.cni.binding.nested:MacvlanDriver
#
def _get_binding_driver(vif):
    mgr = stv_driver.DriverManager(namespace=_BINDING_NAMESPACE,
                                   name=type(vif).__name__,
                                   invoke_on_load=True)
    return mgr.driver
```

所以, 如果 `type(vif).__name__` 为 `VIFOpenVSwitch`, 则 `driver` 为 `kuryr_kubernetes.cni.binding.bridge:VIFOpenVSwitchDriver`.

### <h3 id="4.8.1">4.8.1. openstack/os-vif/os_vif/__init__.py</h3>

```
# openstack/os-vif/os_vif/__init__.py

def plug(vif, instance_info):
    """
    Given a model of a VIF, perform operations to plug the VIF properly.
    :param vif: `os_vif.objects.VIF` object.
    :param instance_info: `os_vif.objects.InstanceInfo` object.
    :raises `exception.LibraryNotInitialized` if the user of the library
            did not call os_vif.initialize(**config) before trying to
            plug a VIF.
    :raises `exception.NoMatchingPlugin` if there is no plugin for the
            type of VIF supplied.
    :raises `exception.PlugException` if anything fails during unplug
            operations.
    """
    if _EXT_MANAGER is None:
        raise os_vif.exception.LibraryNotInitialized()

    plugin_name = vif.plugin
    try:
        plugin = _EXT_MANAGER[plugin_name].obj
    except KeyError:
        raise os_vif.exception.NoMatchingPlugin(plugin_name=plugin_name)

    try:
        LOG.debug("Plugging vif %s", vif)
        plugin.plug(vif, instance_info)
        LOG.info("Successfully plugged vif %s", vif)
    except Exception as err:
        LOG.error("Failed to plug vif %(vif)s",
                  {"vif": vif}, exc_info=True)
        raise os_vif.exception.PlugException(vif=vif, err=err)

def unplug(vif, instance_info):
    """
    Given a model of a VIF, perform operations to unplug the VIF properly.
    :param vif: `os_vif.objects.VIF` object.
    :param instance_info: `os_vif.objects.InstanceInfo` object.
    :raises `exception.LibraryNotInitialized` if the user of the library
            did not call os_vif.initialize(**config) before trying to
            plug a VIF.
    :raises `exception.NoMatchingPlugin` if there is no plugin for the
            type of VIF supplied.
    :raises `exception.UnplugException` if anything fails during unplug
            operations.
    """
    if _EXT_MANAGER is None:
        raise os_vif.exception.LibraryNotInitialized()

    plugin_name = vif.plugin
    try:
        plugin = _EXT_MANAGER[plugin_name].obj
    except KeyError:
        raise os_vif.exception.NoMatchingPlugin(plugin_name=plugin_name)

    try:
        LOG.debug("Unplugging vif %s", vif)
        plugin.unplug(vif, instance_info)
        LOG.info("Successfully unplugged vif %s", vif)
    except Exception as err:
        LOG.error("Failed to unplug vif %(vif)s",
                  {"vif": vif}, exc_info=True)
        raise os_vif.exception.UnplugException(vif=vif, err=err)


def host_info(permitted_vif_type_names=None):
    """
    :param permitted_vif_type_names: list of VIF object names
    Get information about the host platform configuration to be
    provided to the network manager. This will include information
    about what plugins are installed in the host
    If permitted_vif_type_names is not None, the returned HostInfo
    will be filtered such that it only includes plugins which
    support one of the listed VIF types. This allows the caller
    to filter out impls which are not compatible with the current
    usage configuration. For example, to remove VIFVHostUser if
    the guest does not support shared memory.
    :returns: a os_vif.host_info.HostInfo class instance
    """

    if _EXT_MANAGER is None:
        raise os_vif.exception.LibraryNotInitialized()

    plugins = [
        _EXT_MANAGER[name].obj.describe()
        for name in sorted(_EXT_MANAGER.names())
    ]

    info = os_vif.objects.host_info.HostInfo(plugin_info=plugins)
    if permitted_vif_type_names is not None:
        info.filter_vif_types(permitted_vif_type_names)
    return info
```

我们从刚才的 `vif` 对象可知, `vif.plugin` 为 `ovs`, 所以接下来执行的是 `_EXT_MANAGER[plugin_name].obj.plugin()`, 而我们又知:

```
[entry_points]
os_vif =
    linux_bridge = vif_plug_linux_bridge.linux_bridge:LinuxBridgePlugin
    ovs = vif_plug_ovs.ovs:OvsPlugin
```

所以真正调用的是 `vif_plug_ovs.ovs:OvsPlugin:plug()`:

```
# openstack/os-vif/vif_plug_ovs/ovs.py
class OvsPlugin(plugin.PluginBase):
    def plug(self, vif, instance_info):
        if not hasattr(vif, "port_profile"):
            raise exception.MissingPortProfile()
        if not isinstance(vif.port_profile,
                          objects.vif.VIFPortProfileOpenVSwitch):
            raise exception.WrongPortProfile(
                profile=vif.port_profile.__class__.__name__)

        if isinstance(vif, objects.vif.VIFOpenVSwitch):
            if sys.platform != constants.PLATFORM_WIN32:
                linux_net.ensure_ovs_bridge(vif.network.bridge,
                                            self._get_vif_datapath_type(vif))
            else:
                self._plug_vif_windows(vif, instance_info)
        elif isinstance(vif, objects.vif.VIFBridge):
            if sys.platform != constants.PLATFORM_WIN32:
                self._plug_bridge(vif, instance_info)
            else:
                self._plug_vif_windows(vif, instance_info)
        elif isinstance(vif, objects.vif.VIFVHostUser):
            self._plug_vhostuser(vif, instance_info)
        elif isinstance(vif, objects.vif.VIFHostDevice):
            self._plug_vf_passthrough(vif, instance_info)

    def unplug(self, vif, instance_info):
        if not hasattr(vif, "port_profile"):
            raise exception.MissingPortProfile()
        if not isinstance(vif.port_profile,
                          objects.vif.VIFPortProfileOpenVSwitch):
            raise exception.WrongPortProfile(
                profile=vif.port_profile.__class__.__name__)

        if isinstance(vif, objects.vif.VIFOpenVSwitch):
            if sys.platform == constants.PLATFORM_WIN32:
                self._unplug_vif_windows(vif, instance_info)
        elif isinstance(vif, objects.vif.VIFBridge):
            if sys.platform != constants.PLATFORM_WIN32:
                self._unplug_bridge(vif, instance_info)
            else:
                self._unplug_vif_windows(vif, instance_info)
        elif isinstance(vif, objects.vif.VIFVHostUser):
            self._unplug_vhostuser(vif, instance_info)
        elif isinstance(vif, objects.vif.VIFHostDevice):
            self._unplug_vf_passthrough(vif, instance_info)
```

这里真正执行的是 `linux_net.ensure_ovs_bridge()`:

```
# openstack/os-vif/vif_plug_ovs/linux_net.py
@privsep.vif_plug.entrypoint
def ensure_ovs_bridge(bridge, datapath_type):
    _ovs_vsctl(_create_ovs_bridge_cmd(bridge, datapath_type))

def _create_ovs_bridge_cmd(bridge, datapath_type):
    return ['--', '--may-exist', 'add-br', bridge,
            '--', 'set', 'Bridge', bridge, 'datapath_type=%s' % datapath_type]
```

`ensure_ovs_bridge()` 主要确保宿主机上 `ovs br-int` 网桥的存在.

### <h3 id="4.8.2">4.8.2. VIFOpenVSwitchDriver</h3>

```
# kuryr-kubernetes/kuryr_kubernetes/cni/binding/bridge.py
class VIFOpenVSwitchDriver(BaseBridgeDriver):
    def connect(self, vif, ifname, netns):
        super(VIFOpenVSwitchDriver, self).connect(vif, ifname, netns)
        # FIXME(irenab) use pod_id (neutron port device_id)
        instance_id = 'kuryr'
        net_utils.create_ovs_vif_port(vif.bridge_name, vif.vif_name,
                                      vif.port_profile.interface_id,
                                      vif.address, instance_id)

    def disconnect(self, vif, ifname, netns):
        super(VIFOpenVSwitchDriver, self).disconnect(vif, ifname, netns)
        net_utils.delete_ovs_vif_port(vif.bridge_name, vif.vif_name)
```

`super(VIFOpenVSwitchDriver, self).connect()` 主要创建 `veth pair`, 并设置它们的参数， 然后启用这两个 `interface`.

根据 `vif` 中的 `port` 信息通过 `create_ovs_vif_port()` 函数在 `br-int` 网桥上创建对应的 `port`.

#### <h4 id="4.8.2.1">4.8.2.1. BaseBridgeDriver</h4>

```
# kuryr-kubernetes/kuryr_kubernetes/cni/binding/bridge.py
class BaseBridgeDriver(object):
    def connect(self, vif, ifname, netns):
        host_ifname = vif.vif_name

        // container ipdb
        c_ipdb = b_base.get_ipdb(netns)
        // host ipdb
        h_ipdb = b_base.get_ipdb()

        # 创建 veth pair, container 这边的 interface 为 c_iface,
        # 其 container interface name 为参数 ifname, 默认为 eth0
        # host interface name 为参数 host_ifname
        #
        # 另外, neutron 那边申请过来的 port 信息: mac, mtu 都配置给容器 interface
        with c_ipdb.create(ifname=ifname, peer=host_ifname,
                           kind='veth') as c_iface:
            c_iface.mtu = vif.network.mtu
            c_iface.address = str(vif.address)
            c_iface.up()

        if netns:
            with c_ipdb.interfaces[host_ifname] as h_iface:
                h_iface.net_ns_pid = os.getpid()

        with h_ipdb.interfaces[host_ifname] as h_iface:
            h_iface.mtu = vif.network.mtu
            h_iface.up()

    def disconnect(self, vif, ifname, netns):
        pass
```

#### <h4 id="4.8.2.2">4.8.2.2. create_ovs_vif_port</h4>

```
# kuryr-kubernetes/kuryr_kubernetes/linux_net_utils.py
def create_ovs_vif_port(bridge, dev, iface_id, mac, instance_id):
    _ovs_vsctl(_create_ovs_vif_cmd(bridge, dev, iface_id, mac, instance_id))
```

`_create_ovs_vif_cmd()` 执行创建 `port` 的 `ovs-vsctl` 命令:

```
# openstack/os-vif/vif_plug_ovs/linux_net.py
def _create_ovs_vif_cmd(bridge, dev, iface_id, mac,
                        instance_id, interface_type=None,
                        vhost_server_path=None):
    cmd = ['--', '--if-exists', 'del-port', dev, '--',
            'add-port', bridge, dev,
            '--', 'set', 'Interface', dev,
            'external-ids:iface-id=%s' % iface_id,
            'external-ids:iface-status=active',
            'external-ids:attached-mac=%s' % mac,
            'external-ids:vm-uuid=%s' % instance_id]
    if interface_type:
        cmd += ['type=%s' % interface_type]
    if vhost_server_path:
        cmd += ['options:vhost-server-path=%s' % vhost_server_path]
    return cmd
```

### <h3 id="4.8.3">4.8.3. _configure_l3</h3>

```
# kuryr-kubernetes/kuryr_kubernetes/cni/binding/base.py
def _configure_l3(vif, ifname, netns):
    with get_ipdb(netns).interfaces[ifname] as iface:
        for subnet in vif.network.subnets.objects:
            for fip in subnet.ips.objects:
                iface.add_ip(str(fip.address), mask=str(subnet.cidr.netmask))

    routes = get_ipdb(netns).routes
    for subnet in vif.network.subnets.objects:
        for route in subnet.routes.objects:
            routes.add(gateway=str(route.gateway),
                       dst=str(route.cidr)).commit()
        if subnet.gateway:
            routes.add(gateway=str(subnet.gateway),
                       dst='default').commit()
```









