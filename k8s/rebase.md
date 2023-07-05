<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [k8s rebase 的流程概要](#k8s-rebase-%E7%9A%84%E6%B5%81%E7%A8%8B%E6%A6%82%E8%A6%81)
  - [1. 代码 rebase](#1-%E4%BB%A3%E7%A0%81-rebase)
  - [<h2 id="2">2. 重新生成所需的代码和对象</h2>](#h2-id22-%E9%87%8D%E6%96%B0%E7%94%9F%E6%88%90%E6%89%80%E9%9C%80%E7%9A%84%E4%BB%A3%E7%A0%81%E5%92%8C%E5%AF%B9%E8%B1%A1h2)
    - [重新生成 conversion 文件和 deepcopy 文件](#%E9%87%8D%E6%96%B0%E7%94%9F%E6%88%90-conversion-%E6%96%87%E4%BB%B6%E5%92%8C-deepcopy-%E6%96%87%E4%BB%B6)
    - [<h2 id="2.2">重新生成 protobuf objects</h2>](#h2-id22%E9%87%8D%E6%96%B0%E7%94%9F%E6%88%90-protobuf-objectsh2)
    - [重新生成 json (un)marshaling 代码](#%E9%87%8D%E6%96%B0%E7%94%9F%E6%88%90-json-unmarshaling-%E4%BB%A3%E7%A0%81)
  - [3. 更新 Godep](#3-%E6%9B%B4%E6%96%B0-godep)
    - [Godep restore](#godep-restore)
    - [Godep save](#godep-save)
  - [4. k8s 源码编译](#4-k8s-%E6%BA%90%E7%A0%81%E7%BC%96%E8%AF%91)
  - [5. unit test](#5-unit-test)
    - [k8s.io/kubernetes/pkg/api](#k8siokubernetespkgapi)
    - [k8s.io/kubernetes/pkg/util/oom](#k8siokubernetespkgutiloom)
    - [k8s.io/kubernetes/plugin/pkg/scheduler](#k8siokubernetespluginpkgscheduler)
  - [6. integration test](#6-integration-test)
    - [install etcd v3.0.15](#install-etcd-v3015)
    - [ulimit -n 4096](#ulimit--n-4096)
    - [integration test](#integration-test)
  - [7. e2e test](#7-e2e-test)
    - [kube up a k8s cluster](#kube-up-a-k8s-cluster)
    - [Build binaries for testing](#build-binaries-for-testing)
    - [Run all tests](#run-all-tests)
    - [查看 e2e 结果](#%E6%9F%A5%E7%9C%8B-e2e-%E7%BB%93%E6%9E%9C)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# k8s rebase 的流程概要

environment：ubuntu 14.04
golang：1.7.1

k8s rebase to 1.5.1

## 1. 代码 rebase

代码 rebase 工作，解决冲突

## <h2 id="2">2. 重新生成所需的代码和对象</h2>

这部分的东西也可以参考 kubernetes/Makefile 和 kubernetes/Makefile.generated_files 文件。

reference: [api_changes.md](https://github.com/kubernetes/community/blob/master/contributors/devel/api_changes.md)

### 重新生成 conversion 文件和 deepcopy 文件

如果修改了 api 相关的代码，则需要重新生成 conversion 文件和 deepcopy 文件：
    
- pkg/api/<version>/conversion_generated.go
- pkg/apis/extensions/<version>/conversion_generated.go
- <path_to_versioned_api>/zz_generated.deepcopy.go

执行：

```
hack/update-codegen.sh
```

### <h2 id="2.2">重新生成 protobuf objects</h2>

如果修改了 api 相关的代码，可能会涉及到 Protobuf IDL 和 marshallers，所以需要重新生成 protobuf objects

执行：

```
hack/update-generated-protobuf.sh
```


### 重新生成 json (un)marshaling 代码

如果修改了 api 相关的代码，还需要重新生成 json (un)marshaling 代码
    
- pkg/api/<version>/types.generated.go
- pkg/apis/extensions/<version>/types.generated.go

执行：

```
hack/update-codecgen.sh
```

## 3. 更新 Godep

### Godep restore

godep restore 的原理：将 <project_dir>/Godeps/Godeps.json 文件中指定的包通过 go get -d -v 来下载到 GOPATH 路径下。

所以，这里的步骤如下：

首先需要利用上游的 Godeps.json 来做 Godep restore。这一步将上游利用到的 package 全都下载到 GOPATH 路径下：

```
godep restore
```

然后，如果我们的代码用到了新的 package，我们也需要将这些 package 下载到 GOPATH 路径下：

```
go get -v xxxx/yyyy
# 由于我们接下来会做 godep save，所以不需要执行 godep update xxxx/yyyy 来更新 Godeps.json 文件。
```

### Godep save

godep save 的原理：在未指定包名的情况下，godep 会自动扫描当前目录所属包中 import 的所有外部依赖库（非系统库），并将这些依赖库代码拷贝（更新）到 vendor/ 目录下，然后将这些依赖库的当前对应的 revision（commit id）记录到 Godeps/Godeps.json 文件中。

这里执行：

```
hack/godep-save.sh
```

## 4. k8s 源码编译

```
hack/build-go.sh
```

其实就是 make 命令。

## 5. unit test

单元测试最好在 linux 系统下跑（此时也需要在 linux 环境下做编译），如果在 mac 上跑，会出现比较多的问题：比如 shell 命令格式不兼容或者不一样，linux 上有的一些功能组件（apparmor、cgroup等） mac 上没有。

```
hack/test-go.sh
```

其实就是 make test 命令。

### k8s.io/kubernetes/pkg/api

`serialization_proto_test.go` 测试不通过：

1. 要么我们添加的 api 代码不对：重新查看和修改代码
2. 没有重新生成 protobuf objects：重新执行 [### 重新生成 protobuf objects](#2.2)

修改好之后，可单独进行测试：

```
godep go test ./pkg/api
```

### k8s.io/kubernetes/pkg/util/oom

`TestPidListerFailure`（in `oom_linux_test.go`）测试不通过：很有可能是 linux 上未安装/启动 cgroup 服务。

### k8s.io/kubernetes/plugin/pkg/scheduler

`TestCompatibility_v1_Scheduler`（in `compatibility_test.go`）测试不通过：有可能是我们添加了新的 Predicate（in `k8s.io/kubernetes/plugin/pkg/scheduler/algorithmprovider/defaults/defaults.go`），而没有在 `k8s.io/kubernetes/plugin/pkg/scheduler/algorithmprovider/defaults/compatibility_test.go` 中添加相关的测试代码。

## 6. integration test

### install etcd v3.0.15

```
curl -L https://github.com/coreos/etcd/releases/download/v3.0.15/etcd-v3.0.15-linux-amd64.tar.gz -o etcd-v3.0.15-linux-amd64.tar.gz
tar -xzvf etcd-v3.0.15-linux-amd64.tar.gz -C /usr/local/
ln -s /usr/local/etcd-v3.0.15-linux-amd64/etcd /usr/local/bin/etcd
ln -s /usr/local/etcd-v3.0.15-linux-amd64/etcdctl /usr/local/bin/etcdctl
```

### ulimit -n 4096

`ulimit -n 4096`

### integration test

```
./hack/test-integration.sh
```

其实就是 make test-integration 命令。

## 7. e2e test

reference: 

1. [https://github.com/kubernetes/community/blob/master/contributors/devel/e2e-tests.md](https://github.com/kubernetes/community/blob/master/contributors/devel/e2e-tests.md)
2. [https://github.com/kubernetes/kubernetes/tree/master/build](https://github.com/kubernetes/kubernetes/tree/master/build)

**Note**：

```
End-to-end (e2e) tests for Kubernetes provide a mechanism to test end-to-end behavior of the system, and is the last signal to ensure end user operations match developer specifications.
```

### kube up a k8s cluster

用 rebase 后新版本创建一个至少4个节点的 k8s 集群。

可以用 `hack/e2e.go` 来创建 k8s 集群，也可以自己手动创建一个 k8s 集群。

### Build binaries for testing

```
go run hack/e2e.go -v --build
```

### Run all tests

在 master 机器上跑，最好是并行测试（加上 GINKGO_PARALLEL=y），速度快：

```
# Run all tests in parallel
GINKGO_PARALLEL=y KUBERNETES_PROVIDER=caicloud-baremetal go run hack/e2e.go --v --test
```

**Note**：

如果部署的 k8s 是已 https 访问，而证书又是自签证书，可能会出现如下问题：

```
Jan 21 01:33:48.277: INFO: Unexpected error listing nodes: Get https://192.168.16.37/api/v1/nodes?fieldSelector=spec.unschedulable%3Dfalse&resourceVersion=0: x509: certificate signed by unknown authority
```

那么，解决办法如下：

```
# 通过 kubectl config get-clusters 获取 cluster_name
# 在 master 上执行如下命令，~/.kube/config 也会被自动更新
kubectl config set-cluster <cluster name> --insecure-skip-tls-verify=true --server=https://<server_ip:port>
```

上面的这个命令和每次执行 `kubectl` 时加上参数 `--insecure-skip-tls-verify=true` 的效果时一样的。

### 查看 e2e 结果

根据 e2e 测试的结果修改 bug 吧。
