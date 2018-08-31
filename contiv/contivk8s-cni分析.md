# cni 插件

kubelet 调用 cni 二进制文件执行时, 参数传递由两部分组成, 一部分通过 `env` 环境变量传入, 这部分主要是 `cni` 插件执行 `ADD` 或者 `DEL` 函数时所需要的参数：

```
CNI_COMMAND=ADD/DEL
CNI_CONTAINERID=xxxxxxxxxxxxxxxxxxx
CNI_NETNS=/proc/4390/ns/net
CNI_ARGS=IgnoreUnknown=1;K8S_POD_NAMESPACE=default;K8S_POD_NAME=22-my-nginx-2523304718-7stgs;K8S_POD_INFRA_CONTAINER_ID=xxxxxxxxxxxxxxxx
CNI_IFNAME=eth0
CNI_PATH=/opt/cni/bin
```

另一部分通过 `stdin` 传入, 这里主要是指 `kubelet` 使用的 `cni` 插件的配置文件(`json` 格式, 比如 `etc/cni/net.d/xxxx.conf`)的内容将以流的方式传入.

# cni 插件代码流程

1. contivk8s cni 插件其实是一个代理，kubelet 调用 contivk8s cni 创建和删除 pod 的请求都会代理到 netplugin 实例上，并又 netplugin 实例负责添加和删除 pod 到 contiv 网络。
2. 创建的 pod 需要有如下 label:
```
apiVersion: v1
kind: Pod
metadata:
  name: test
  # Note that the Pod does not need to be in the same namespace as the loader.
  labels:
    io.contiv.tenant: xxxx
    io.contiv.network: xxxx
    io.contiv.net-group: xxxx
```

**mgmtfn/k8splugin/contivk8s/k8s_cni.go**

func main() {

    mainfunc()
}

func mainfunc() {
    pInfo := cniapi.CNIPodAttr{}
    cniCmd := os.Getenv("CNI_COMMAND")

    // Open a logfile
    f, err := os.OpenFile("/var/log/contivk8s.log", os.O_RDWR|os.O_CREATE|os.O_APPEND, 0666)
    if err != nil {
        logger.Fatalf("error opening file: %v", err)
    }
    defer f.Close()

    logger.SetOutput(f)
    log = getPrefixedLogger()

    log.Infof("==> Start New Log <==\n")
    log.Infof("command: %s, cni_args: %s", cniCmd, os.Getenv("CNI_ARGS"))

    // 获取 kubelet 传过来的参数信息
    // Collect information passed by CNI
    err = getPodInfo(&pInfo)
    if err != nil {
        log.Fatalf("Error parsing environment. Err: %v", err)
    }

    nc := clients.NewNWClient()
    // 向 netplugin 实例发送 pod 添加和删除请求
    if cniCmd == "ADD" {
        addPodToContiv(nc, &pInfo)
    } else if cniCmd == "DEL" {
        deletePodFromContiv(nc, &pInfo)
    }

}

# 添加 pod 到 contiv 网络

**mgmtfn/k8splugin/contivk8s/k8s_cni.go**

func addPodToContiv(nc *clients.NWClient, pInfo *cniapi.CNIPodAttr) {

    // Add to contiv network
    result, err := nc.AddPod(pInfo)
    if err != nil || result.Result != 0 {
        log.Errorf("EP create failed for pod: %s/%s",
            pInfo.K8sNameSpace, pInfo.Name)
        cerr := CNIError{}
        cerr.CNIVersion = "0.3.1"

        if result != nil {
            cerr.Code = result.Result
            cerr.Msg = "Contiv:" + result.ErrMsg
            cerr.Details = result.ErrInfo
        } else {
            cerr.Code = 1
            cerr.Msg = "Contiv:" + err.Error()
        }

        eOut, err := json.Marshal(&cerr)
        if err == nil {
            log.Infof("cniErr: %s", eOut)
            fmt.Printf("%s", eOut)
        } else {
            log.Errorf("JSON error: %v", err)
        }
        os.Exit(1)
    }

    log.Infof("EP created IP: %s\n", result.IPAddress)
    // Write the ip address of the created endpoint to stdout

    // ParseCIDR returns a reference to IPNet
    ip4Net, err := ip.ParseCIDR(result.IPAddress)
    if err != nil {
        log.Errorf("Failed to parse IPv4 CIDR: %v", err)
        return
    }

    out := CNIResponse{
        CNIVersion: "0.3.1",
    }

    out.IPs = append(out.IPs, &cni.IPConfig{
        Version: "4",
        Address: net.IPNet{IP: ip4Net.IP, Mask: ip4Net.Mask},
    })

    if result.IPv6Address != "" {
        ip6Net, err := ip.ParseCIDR(result.IPv6Address)
        if err != nil {
            log.Errorf("Failed to parse IPv6 CIDR: %v", err)
            return
        }

        out.IPs = append(out.IPs, &cni.IPConfig{
            Version: "6",
            Address: net.IPNet{IP: ip6Net.IP, Mask: ip6Net.Mask},
        })
    }

    data, err := json.MarshalIndent(out, "", "    ")
    if err != nil {
        log.Errorf("Failed to marshal json: %v", err)
        return
    }

    log.Infof("Response from CNI executable: \n%s", fmt.Sprintf("%s", data))
    fmt.Printf(fmt.Sprintf("%s", data))
}

**mgmtfn/k8splugin/contivk8s/clients/network.go**

// AddPod adds a pod to contiv using the cni api
func (c *NWClient) AddPod(podInfo interface{}) (*cniapi.RspAddPod, error) {

    data := cniapi.RspAddPod{}
    buf, err := json.Marshal(podInfo)
    if err != nil {
        return nil, err
    }

    body := bytes.NewBuffer(buf)
    url := c.baseURL + cniapi.EPAddURL
    r, err := c.client.Post(url, "application/json", body)
    if err != nil {
        return nil, err
    }
    defer r.Body.Close()

    switch {
    case r.StatusCode == int(404):
        return nil, fmt.Errorf("page not found")

    case r.StatusCode == int(403):
        return nil, fmt.Errorf("access denied")

    case r.StatusCode == int(500):
        info, err := ioutil.ReadAll(r.Body)
        if err != nil {
            return nil, err
        }
        err = json.Unmarshal(info, &data)
        if err != nil {
            return nil, err
        }
        return &data, fmt.Errorf("internal server error")

    case r.StatusCode != int(200):
        log.Errorf("POST Status '%s' status code %d \n", r.Status, r.StatusCode)
        return nil, fmt.Errorf("%s", r.Status)
    }

    response, err := ioutil.ReadAll(r.Body)
    if err != nil {
        return nil, err
    }

    err = json.Unmarshal(response, &data)
    if err != nil {
        return nil, err
    }

    return &data, nil
}


# 从 contiv 网络删除 pod

**mgmtfn/k8splugin/contivk8s/k8s_cni.go**

func deletePodFromContiv(nc *clients.NWClient, pInfo *cniapi.CNIPodAttr) {

    err := nc.DelPod(pInfo)
    if err != nil {
        log.Errorf("DelEndpoint returned %v", err)
    } else {
        log.Infof("EP deleted pod: %s\n", pInfo.Name)
    }
}

// DelPod deletes a pod from contiv using the cni api
func (c *NWClient) DelPod(podInfo interface{}) error {

    buf, err := json.Marshal(podInfo)
    if err != nil {
        return err
    }

    body := bytes.NewBuffer(buf)
    url := c.baseURL + cniapi.EPDelURL
    r, err := c.client.Post(url, "application/json", body)
    if err != nil {
        return err
    }
    defer r.Body.Close()

    switch {
    case r.StatusCode == int(404):
        return fmt.Errorf("page not found")
    case r.StatusCode == int(403):
        return fmt.Errorf("access denied")
    case r.StatusCode != int(200):
        log.Errorf("GET Status '%s' status code %d \n", r.Status, r.StatusCode)
        return fmt.Errorf("%s", r.Status)
    }

    return nil
}

# References

1. [kuryr cni](../kuryr-cni.md)
2. https://thenewstack.io/hackers-guide-kubernetes-networking/
3. https://github.com/containernetworking/cni/blob/master/SPEC.md
