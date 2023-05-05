<!-- TOC -->

- [work-notes](#work-notes)
    - [AIGC](#aigc)
    - [APM](#apm)
    - [容器相关](#容器相关)
    - [others](#others)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

<a id="markdown-work-notes" name="work-notes"></a>
# work-notes

好记性不如烂笔头

<a id="markdown-aigc" name="aigc"></a>
## AIGC

- [openai embedding 详解](aigc/openai_text_embedding.md)
- [what is autogpt](aigc/what_is_autogpt.md)
- [autogpt 架构详解](aigc/autogpt_architecture.md)
- [autogpt 源码详解](aigc/autogpt_details.md)

<a id="markdown-apm" name="apm"></a>
## APM

- [基本概念](apm/apm.md)
- [服务端 apm](apm/服务端-apm.md)
- [移动应用端 apm](apm/移动应用端-apm.md)

<a id="markdown-容器相关" name="容器相关"></a>
## 容器相关

- 阿里云 terway 详解
    - [阿里云 terway 详解](terway/terway.md)
    - [ppt slide: 阿里云如何构建高性能云原生容器网络](terway/Terway-详解.pdf)
- openstack neutron 网络分析
    - [云计算几个 ip 的概念](openstack/neutron/ip_types.md)
    - [neutron networking architecture](openstack/neutron/neutron.md)
    - [openstack 分布式虚拟路由](openstack/neutron/dvr.md)
- [netapp trident 源码分析](netapp-trident/trident.md)
- [异地多活](multi-site-ha/msha.md)
- kuryr-kubernetes
    - [openstack curl](kuryr-kubernetes/openstack_curl.md)
    - [kuryr k8s controller](kuryr-kubernetes/kuryr-k8s-controller.md)
    - [kuryr cni](kuryr-kubernetes/kuryr-cni.md)
- k8s operator 分析和 example 详解
    - [markdown: k8s operator 分析和 example 详解](k8s-operator-example/readme.md)
    - [pdf: k8s operator 分析和 example 详解](k8s-operator-example/readme.pdf)
- [contiv 分析](contiv/README.md)
- k8s cache 分析
    - [store_indexer](cache/Store_Indexer.md)
    - [queue_fifo](cache/Queue_FIFO.md)
    - [listers](cache/listers.md)
- dynamic-volume-provisioner
    - [nfs-client-provisioner源码分析](dynamic-volume-provisioner/nfs-client-provisioner源码分析.webarchive)
    - [利用NFS动态提供Kubernetes后端存储卷](dynamic-volume-provisioner/利用NFS动态提供Kubernetes后端存储卷.webarchive)
    - [Kubernetes存储概览-Volume-Provisioner代码分析](dynamic-volume-provisioner/Kubernetes存储概览-Volume-Provisioner代码分析.pdf)
- k8s volume 分析
    - [k8s volume 详解](volume/volume.md)
    - [pv & pvc](volume/pv_pvc.md)
    - [k8s nfs volume 详解](volume/nfs-plugin.md)
- [k8s wait package 分析](wait/wait.md)
- [k8s api 机制](api.md)
- [kube-proxy 关键代码流程分析](kube-proxy.md)
- [Kubernetes ResourceQuota Controller内部实现原理及源码分析](Kubernetes-ResourceQuota-Controller内部实现原理及源码分析.webarchive)
- [k8s rebase 的流程概要](rebase.md)
- [k8s 对存储的要求](require-for-storage.md)
- cni 相关
    - [kuryr-cni分析](https://github.com/keontang/work-notes/blob/master/kuryr-kubernetes/kuryr-cni.md)
    - [contivk8s-cni分析](https://github.com/keontang/work-notes/blob/master/contiv/contivk8s-cni%E5%88%86%E6%9E%90.md)
    - [macvlan cni 分析](https://github.com/keontang/knowhow/blob/main/ipvlan-macvlan/macvlan-cni.md)

<a id="markdown-others" name="others"></a>
## others

- [Numbers Everyone Should Know](numbers-everyone-should-know.md)
- [yaml 格式中字符串跨多行的格式方法](yaml.md)
- [spark 介绍](spark/README.md)
- [knowhow](https://github.com/keontang/knowhow)
