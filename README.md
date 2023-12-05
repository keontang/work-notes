<!-- TOC -->

- [work-notes](#work-notes)
    - [AIGC](#aigc)
    - [APM](#apm)
    - [容器相关](#容器相关)
    - [DDD](#ddd)
    - [others](#others)

<!-- /TOC -->
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

- [basic knowledge](aigc/basic)
- [openai embedding 详解](aigc/openai_text_embedding.md)
- [what is autogpt](aigc/what_is_autogpt.md)
- [autogpt 架构详解](aigc/autogpt_architecture.md)
- [autogpt 源码详解](aigc/autogpt_details.md)
- [transformer 理解](aigc/transformer/details.md)
- [一文搞懂RNN（循环神经网络）基础篇](aigc/rnn1.md)
- [循环神经网络 – Recurrent Neural Network | RNN](aigc/rnn2.md)
- [RNN 扩展](aigc/rnn3.md)
- [A Complete LangChain Guide](aigc/langchain_details.md)

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
- [k8s api 机制](k8s/api.md)
- [kube-proxy 关键代码流程分析](k8s/kube-proxy.md)
- [Kubernetes ResourceQuota Controller内部实现原理及源码分析](k8s/Kubernetes-ResourceQuota-Controller内部实现原理及源码分析.webarchive)
- [k8s rebase 的流程概要](k8s/rebase.md)
- [k8s 对存储的要求](k8s/require-for-storage.md)
- cni 相关
    - [k8s cni 相关](k8s/kubernetes-network.md)
    - [kuryr-cni分析](kuryr-kubernetes/kuryr-cni.md)
    - [contivk8s-cni分析](contiv/contivk8s-cni%E5%88%86%E6%9E%90.md)
    - [macvlan cni 分析](https://github.com/keontang/knowhow/blob/main/ipvlan-macvlan/macvlan-cni.md)
- [nvidia docker 介绍](k8s/nvidia-docker.md)
- [clean null docker image script](k8s/clean-null-docker-image.sh)
- [delete terminating namespace script](k8s/delete_terminating_namespace.sh)

<a id="markdown-ddd" name="ddd"></a>
## DDD

- [强烈推荐 awesome-go-education 中的 DDD](https://mehdihadeli.github.io/awesome-go-education/ddd/)
- [DDD 领域驱动设计落地实践：六步拆解 DDD](DDD/1.md)
- [一文扫清DDD核心概念理解障碍](DDD/2.md)
- [DDD领域驱动设计落地实践：微服务拆分之道](DDD/3.md)
- [可落地的DDD编码实践（代码结构）](DDD/4.md)
- [DDD的类命名规范](DDD/5.md)
- [领域驱动模型 VO、DTO、DO、PO 概念及其区别](DDD/6.md)
- [客户管理系统微服务化实战-PartI](DDD/7.md)
- [领域模型映射代码结构](DDD/8.md)
- [DDD领域驱动设计之聚合根、实体、值对象](DDD/9.md)

<a id="markdown-others" name="others"></a>
## others

- [ipv4 & ipv6 双栈](others/dual-stack-base.md)
- [Numbers Everyone Should Know](others/numbers-everyone-should-know.md)
- [一文搞懂高并发性能指标：QPS、TPS、RT、并发数、吞吐量，以及计算公式](others/high-throughput-metrics.md)
- [yaml 格式中字符串跨多行的格式方法](others/yaml.md)
- [spark 介绍](spark/README.md)
- [knowhow](https://github.com/keontang/knowhow)
- [Software Engineering Advice from Building Large-Scale Distributed Systems (Jeff Dean)](others/Software_Engineering_Advice_from_Building_Large-Scale_Distributed_Systems.pdf)
- [Designs, Lessons and Advice from Building Large Distributed Systems(Jeff Dean)](others/dean-keynote-ladis2009-scalable-distributed-google.pdf)
