源码 1.6

**目录**

- [Volume 相关分析](#1)
    - [Volume 相关 interface 和 struct](#1.1)
        - [Volume interface](#1.1.1)
        - [MetricsProvider interface](#1.1.2)
        - [Mounter interface](#1.1.3)
        - [Unmounter interface](#1.1.4)
        - [Provisioner interface](#1.1.5)
        - [Deleter interface](#1.1.6)
        - [Attacher interface](#1.1.7)
        - [BulkVolumeVerifier interface](#1.1.8)
        - [Detacher interface](#1.1.9)
    - [VolumePlugin 相关 interface 和 struct](#1.2)
        - [VolumePlugin interface](#1.2.1)
        - [PersistentVolumePlugin interface](#1.2.2)
        - [RecyclableVolumePlugin interface](#1.2.3)
        - [DeletableVolumePlugin interface](#1.2.4)
        - [ProvisionableVolumePlugin interface](#1.2.5)
        - [AttachableVolumePlugin interface](#1.2.6)
        - [VolumePluginMgr struct](#1.2.7)
    - [kubelet 启动时注册和初始化 volume plugins](#1.3)
        - [注册 volume plugins](#1.3.1)
        - [初始化 volume plugins](#1.3.2)
    - [Attach/Detach Controller 分析](#1.4)
        - [功能分析](#1.4.1)
        - [关键代码分析](#1.4.2)
    - [pv Controller 分析](#1.5)
    - [kubelet volumemanager 分析](#1.6)
    - [operationexecutor 分析](#1.7)
- [References](#2)

<h1 id='1'># Volume 相关分析</h1>

<h2 id='1.1'>## Volume 相关 interface 和 struct</h2>

<h3 id='1.1.1'>### Volume interface</h3>

```
// pkg/volume/volume.go

// Volume represents a directory used by pods or hosts on a node. All method
// implementations of methods in the volume interface must be idempotent.
type Volume interface {
    // GetPath returns the path to which the volume should be mounted for the
    // pod.
    GetPath() string

    // MetricsProvider embeds methods for exposing metrics (e.g.
    // used, available space).
    MetricsProvider
}
```

<h3 id='1.1.2'>### MetricsProvider interface</h3>

```
// pkg/volume/volume.go

// MetricsProvider exposes metrics (e.g. used,available space) related to a
// Volume.
type MetricsProvider interface {
    // GetMetrics returns the Metrics for the Volume. Maybe expensive for
    // some implementations.
    GetMetrics() (*Metrics, error)
}
```

<h3 id='1.1.3'>### Mounter interface</h3>

`Mounter` 接口提供方法为 pod 挂载 volume.

```
// pkg/volume/volume.go

// Mounter interface provides methods to set up/mount the volume.
type Mounter interface {
    // Uses Interface to provide the path for Docker binds.
    Volume

    // CanMount is called immediately prior to Setup to check if
    // the required components (binaries, etc.) are available on
    // the underlying node to complete the subsequent SetUp (mount)
    // operation. If CanMount returns error, the mount operation is
    // aborted and an event is generated indicating that the node
    // does not have the required binaries to complete the mount.
    // If CanMount succeeds, the mount operation continues
    // normally. The CanMount check can be enabled or disabled
    // using the experimental-check-mount-binaries binary flag
    CanMount() error

    // SetUp prepares and mounts/unpacks the volume to a
    // self-determined directory path. The mount point and its
    // content should be owned by 'fsGroup' so that it can be
    // accessed by the pod. This may be called more than once, so
    // implementations must be idempotent.
    SetUp(fsGroup *types.UnixGroupID) error
    // SetUpAt prepares and mounts/unpacks the volume to the
    // specified directory path, which may or may not exist yet.
    // The mount point and its content should be owned by
    // 'fsGroup' so that it can be accessed by the pod. This may
    // be called more than once, so implementations must be
    // idempotent.
    SetUpAt(dir string, fsGroup *types.UnixGroupID) error
    // GetAttributes returns the attributes of the mounter.
    GetAttributes() Attributes
}
```

<h3 id='1.1.4'>### Unmounter interface</h3>

`Unmounter` 接口提供方法为 pod 卸载 volume.

```
// pkg/volume/volume.go

// Unmounter interface provides methods to cleanup/unmount the volumes.
type Unmounter interface {
    Volume
    // TearDown unmounts the volume from a self-determined directory and
    // removes traces of the SetUp procedure.
    TearDown() error
    // TearDown unmounts the volume from the specified directory and
    // removes traces of the SetUp procedure.
    TearDownAt(dir string) error
}
```

<h3 id='1.1.5'>### Provisioner interface</h3>

`Provisioner` 通过底层的存储系统来创建 PersistentVolume.

```
// pkg/volume/volume.go

// Provisioner is an interface that creates templates for PersistentVolumes
// and can create the volume as a new resource in the infrastructure provider.
type Provisioner interface {
    // Provision creates the resource by allocating the underlying volume in a
    // storage system. This method should block until completion and returns
    // PersistentVolume representing the created storage resource.
    Provision() (*v1.PersistentVolume, error)
}
```

<h3 id='1.1.6'>### Deleter interface</h3>

删除 volume 资源时, `Deleter` 负责删除底层的存储系统对应的资源.

```
// pkg/volume/volume.go

// Deleter removes the resource from the underlying storage provider. Calls
// to this method should block until the deletion is complete. Any error
// returned indicates the volume has failed to be reclaimed. A nil return
// indicates success.
type Deleter interface {
    Volume
    // This method should block until completion.
    // deletedVolumeInUseError returned from this function will not be reported
    // as error and it will be sent as "Info" event to the PV being deleted. The
    // volume controller will retry deleting the volume in the next periodic
    // sync. This can be used to postpone deletion of a volume that is being
    // detached from a node. Deletion of such volume would fail anyway and such
    // error would confuse users.
    Delete() error
}
```

<h3 id='1.1.7'>### Attacher interface</h3>

`Attacher` 负责将 volume device 安装到 node 上, 比如 linux 的设备路径一般在 `/dev/` 目录下面.

```
// pkg/volume/volume.go

// Attacher can attach a volume to a node.
type Attacher interface {
    // Attaches the volume specified by the given spec to the node with the given Name.
    // On success, returns the device path where the device was attached on the
    // node.
    Attach(spec *Spec, nodeName types.NodeName) (string, error)

    // VolumesAreAttached checks whether the list of volumes still attached to the specified
    // node. It returns a map which maps from the volume spec to the checking result.
    // If an error is occurred during checking, the error will be returned
    VolumesAreAttached(specs []*Spec, nodeName types.NodeName) (map[*Spec]bool, error)

    // WaitForAttach blocks until the device is attached to this
    // node. If it successfully attaches, the path to the device
    // is returned. Otherwise, if the device does not attach after
    // the given timeout period, an error will be returned.
    WaitForAttach(spec *Spec, devicePath string, timeout time.Duration) (string, error)

    // GetDeviceMountPath returns a path where the device should
    // be mounted after it is attached. This is a global mount
    // point which should be bind mounted for individual volumes.
    GetDeviceMountPath(spec *Spec) (string, error)

    // MountDevice mounts the disk to a global path which
    // individual pods can then bind mount
    MountDevice(spec *Spec, devicePath string, deviceMountPath string) error
}
```

<h3 id='1.1.8'>### BulkVolumeVerifier interface</h3>

```
// pkg/volume/volume.go

type BulkVolumeVerifier interface {
    // BulkVerifyVolumes checks whether the list of volumes still attached to the
    // the clusters in the node. It returns a map which maps from the volume spec to the checking result.
    // If an error occurs during check - error should be returned and volume on nodes
    // should be assumed as still attached.
    BulkVerifyVolumes(volumesByNode map[types.NodeName][]*Spec) (map[types.NodeName]map[*Spec]bool, error)
}
```

<h3 id='1.1.9'>### Detacher interface</h3>

`Detacher` 负责将 volume device 从 node 上删除.

```
// pkg/volume/volume.go

// Detacher can detach a volume from a node.
type Detacher interface {
    // Detach the given device from the node with the given Name.
    Detach(deviceName string, nodeName types.NodeName) error

    // UnmountDevice unmounts the global mount of the disk. This
    // should only be called once all bind mounts have been
    // unmounted.
    UnmountDevice(deviceMountPath string) error
}
```

<h2 id='1.2'>## VolumePlugin 相关 interface 和 struct</h2>

<h3 id='1.2.1'>### VolumePlugin interface</h3>

`VolumePlugin` 是 kubelet 调用当前 node 上的 volume plugin 的一个接口, kubelet 通过该接口实例化和管理 volume. 每一个 volume plugin 需要实现 `VolumePlugin interface` 中定义的方法.

```
// pkg/volume/plugins.go

// VolumePlugin is an interface to volume plugins that can be used on a
// kubernetes node (e.g. by kubelet) to instantiate and manage volumes.
type VolumePlugin interface {
    // Init initializes the plugin.  This will be called exactly once
    // before any New* calls are made - implementations of plugins may
    // depend on this.
    // kubelet 启动时调用该方法初始化 plugin
    Init(host VolumeHost) error

    // Name returns the plugin's name.  Plugins must use namespaced names
    // such as "example.com/volume" and contain exactly one '/' character.
    // The "kubernetes.io" namespace is reserved for plugins which are
    // bundled with kubernetes.
    // "kubernetes.io" 这个 namespace 预留给 in-tree 的 volume plugins
    GetPluginName() string

    // GetVolumeName returns the name/ID to uniquely identifying the actual
    // backing device, directory, path, etc. referenced by the specified volume
    // spec.
    // For Attachable volumes, this value must be able to be passed back to
    // volume Detach methods to identify the device to act on.
    // If the plugin does not support the given spec, this returns an error.
    GetVolumeName(spec *Spec) (string, error)

    // CanSupport tests whether the plugin supports a given volume
    // specification from the API.  The spec pointer should be considered
    // const.
    // 测试 plugin 是否支持指定规格的卷
    CanSupport(spec *Spec) bool

    // RequiresRemount returns true if this plugin requires mount calls to be
    // reexecuted. Atomically updating volumes, like Downward API, depend on
    // this to update the contents of the volume.
    RequiresRemount() bool

    // NewMounter creates a new volume.Mounter from an API specification.
    // Ownership of the spec pointer in *not* transferred.
    // - spec: The v1.Volume spec
    // - pod: The enclosing pod
    // 返回一个 Mounter 接口
    // kubelet 利用 Mounter 接口将 volume mount 到指定路径, 从而能被 pod 访问
    NewMounter(spec *Spec, podRef *v1.Pod, opts VolumeOptions) (Mounter, error)

    // NewUnmounter creates a new volume.Unmounter from recoverable state.
    // - name: The volume name, as per the v1.Volume spec.
    // - podUID: The UID of the enclosing pod
    // 返回一个 Unmounter 接口
    // kubelet 利用 Unmounter 接口 将 volume 从指定路径上 unmount
    NewUnmounter(name string, podUID types.UID) (Unmounter, error)

    // ConstructVolumeSpec constructs a volume spec based on the given volume name
    // and mountPath. The spec may have incomplete information due to limited
    // information from input. This function is used by volume manager to reconstruct
    // volume spec by reading the volume directories from disk
    ConstructVolumeSpec(volumeName, mountPath string) (*Spec, error)

    // SupportsMountOption returns true if volume plugins supports Mount options
    // Specifying mount options in a volume plugin that doesn't support
    // user specified mount options will result in error creating persistent volumes
    SupportsMountOption() bool

    // SupportsBulkVolumeVerification checks if volume plugin type is capable
    // of enabling bulk polling of all nodes. This can speed up verification of
    // attached volumes by quite a bit, but underlying pluging must support it.
    SupportsBulkVolumeVerification() bool
}
```

<h3 id='1.2.2'>### PersistentVolumePlugin interface</h3>

```
// pkg/volume/plugins.go

// PersistentVolumePlugin is an extended interface of VolumePlugin and is used
// by volumes that want to provide long term persistence of data
type PersistentVolumePlugin interface {
    VolumePlugin
    // GetAccessModes describes the ways a given volume can be accessed/mounted.
    GetAccessModes() []v1.PersistentVolumeAccessMode
}
```

Persistent Volume 有三种访问方式:

```
// pkg/api/types.go

type PersistentVolumeAccessMode string

const (
    // can be mounted read/write mode to exactly 1 host
    ReadWriteOnce PersistentVolumeAccessMode = "ReadWriteOnce"
    // can be mounted in read-only mode to many hosts
    ReadOnlyMany PersistentVolumeAccessMode = "ReadOnlyMany"
    // can be mounted in read/write mode to many hosts
    ReadWriteMany PersistentVolumeAccessMode = "ReadWriteMany"
)
```

<h3 id='1.2.3'>### RecyclableVolumePlugin interface</h3>

```
// pkg/volume/plugins.go

// RecyclableVolumePlugin is an extended interface of VolumePlugin and is used
// by persistent volumes that want to be recycled before being made available
// again to new claims
type RecyclableVolumePlugin interface {
    VolumePlugin

    // Recycle knows how to reclaim this
    // resource after the volume's release from a PersistentVolumeClaim.
    // Recycle will use the provided recorder to write any events that might be
    // interesting to user. It's expected that caller will pass these events to
    // the PV being recycled.
    Recycle(pvName string, spec *Spec, eventRecorder RecycleEventRecorder) error
}
```

<h3 id='1.2.4'>### DeletableVolumePlugin interface</h3>

```
// pkg/volume/plugins.go

// DeletableVolumePlugin is an extended interface of VolumePlugin and is used
// by persistent volumes that want to be deleted from the cluster after their
// release from a PersistentVolumeClaim.
type DeletableVolumePlugin interface {
    VolumePlugin
    // NewDeleter creates a new volume.Deleter which knows how to delete this
    // resource in accordance with the underlying storage provider after the
    // volume's release from a claim
    NewDeleter(spec *Spec) (Deleter, error)
}
```

<h3 id='1.2.5'>### ProvisionableVolumePlugin interface</h3>

```
// pkg/volume/plugins.go

// ProvisionableVolumePlugin is an extended interface of VolumePlugin and is
// used to create volumes for the cluster.
type ProvisionableVolumePlugin interface {
    VolumePlugin
    // NewProvisioner creates a new volume.Provisioner which knows how to
    // create PersistentVolumes in accordance with the plugin's underlying
    // storage provider
    NewProvisioner(options VolumeOptions) (Provisioner, error)
}
```

<h3 id='1.2.6'>### AttachableVolumePlugin interface</h3>

```
// pkg/volume/plugins.go

// AttachableVolumePlugin is an extended interface of VolumePlugin and is used for volumes that require attachment
// to a node before mounting.
type AttachableVolumePlugin interface {
    VolumePlugin
    NewAttacher() (Attacher, error)
    NewDetacher() (Detacher, error)
    GetDeviceMountRefs(deviceMountPath string) ([]string, error)
}
```

<h3 id='1.2.7'>### VolumePluginMgr struct</h3>

kubelet 通过 `VolumePluginMgr struct` 管理所有注册的 volume plugins.

```
// pkg/volume/plugins.go

// VolumePluginMgr tracks registered plugins.
type VolumePluginMgr struct {
    mutex   sync.Mutex
    plugins map[string]VolumePlugin
}
```

<h2 id='1.3'>## kubelet 启动时注册和初始化 volume plugins</h2>

```
// cmd/kubelet/app/server.go

func run(s *options.KubeletServer, kubeDeps *kubelet.KubeletDeps) (err error) {
    ...
    if kubeDeps == nil {
        ...
        // 初始化 KubeletDeps 结构时查找所有可用的 volume plugins
        kubeDeps, err = UnsecuredKubeletDeps(s)
    }
    ...
    // 根据 kubelet 的运行参数运行 kubelet
    if err := RunKubelet(&s.KubeletConfiguration, kubeDeps, s.RunOnce, standaloneMode); err != nil {
        return err
    }
    ...
}
```

<h3 id='1.3.1'>### 注册 volume plugins</h3>

`UnsecuredKubeletDeps` 函数通过调用 `ProbeVolumePlugins` 函数注册所有可用的 volume plugins.

```
// cmd/kubelet/app/server.go

// UnsecuredKubeletDeps returns a KubeletDeps suitable for being run, or an error if the server setup
// is not valid.  It will not start any background processes, and does not include authentication/authorization
func UnsecuredKubeletDeps(s *options.KubeletServer) (*kubelet.KubeletDeps, error) {
    ...
    return &kubelet.KubeletDeps{
        ...
        // 注册所有可用的 volume plugins
        VolumePlugins:     ProbeVolumePlugins(s.VolumePluginDir),
        ...
    }
}
```

`ProbeVolumePlugins` 函数注册的 volume plugins 分两类. 

第一类为所有的 in-tree volume plugins, 这一类都是通过调用具体的 volume plugin 的 ProbeVolumePlugins 函数来注册, 比如: `gce_pd.ProbeVolumePlugins()`.

第二类为所有的 out-of-tree volume plugins (第三方插件), 即 flex volume plugins, 这一类 volume plugins 都统一放在 `VolumePluginDir` 目录下 (用户可以通过 kubelet options 来设置 `VolumePluginDir` 目录, k8s 默认存放在 `/usr/libexec/kubernetes/kubelet-plugins/volume/exec/`), `VolumePluginDir` 目录下的每一个子目录都被认为是一个 flex volume plugin, 这一类通过 `flexvolume.ProbeVolumePlugins` 函数来注册.

```
// cmd/kubelet/app/plugins.go

// ProbeVolumePlugins collects all volume plugins into an easy to use list.
// PluginDir specifies the directory to search for additional third party
// volume plugins.
func ProbeVolumePlugins(pluginDir string) []volume.VolumePlugin {
    allPlugins := []volume.VolumePlugin{}

    // The list of plugins to probe is decided by the kubelet binary, not
    // by dynamic linking or other "magic".  Plugins will be analyzed and
    // initialized later.
    //
    // Kubelet does not currently need to configure volume plugins.
    // If/when it does, see kube-controller-manager/app/plugins.go for example of using volume.VolumeConfig
    allPlugins = append(allPlugins, aws_ebs.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, empty_dir.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, gce_pd.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, git_repo.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, host_path.ProbeVolumePlugins(volume.VolumeConfig{})...)
    allPlugins = append(allPlugins, nfs.ProbeVolumePlugins(volume.VolumeConfig{})...)
    allPlugins = append(allPlugins, secret.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, iscsi.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, glusterfs.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, rbd.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, cinder.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, quobyte.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, cephfs.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, downwardapi.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, fc.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, flocker.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, flexvolume.ProbeVolumePlugins(pluginDir)...)
    allPlugins = append(allPlugins, azure_file.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, configmap.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, vsphere_volume.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, azure_dd.ProbeVolumePlugins()...)
    allPlugins = append(allPlugins, photon_pd.ProbeVolumePlugins()...)
    return allPlugins
}
```

下面我们看看 `gce_pd.ProbeVolumePlugins` 函数:

```
// pkg/volume/gce_pd/gce_pd.go

// This is the primary entrypoint for volume plugins.
func ProbeVolumePlugins() []volume.VolumePlugin {
    return []volume.VolumePlugin{&gcePersistentDiskPlugin{nil}}
}
```

然后我们再看看 `flexvolume.ProbeVolumePlugins` 函数:

```
// pkg/volume/flexvolume/flexvolume.go

// This is the primary entrypoint for volume plugins.
func ProbeVolumePlugins(pluginDir string) []volume.VolumePlugin {
    plugins := []volume.VolumePlugin{}

    files, _ := ioutil.ReadDir(pluginDir)
    // pluginDir 目录下的每一个子目录都被认为是一个 flex volume plugin
    for _, f := range files {
        // only directories are counted as plugins
        // and pluginDir/dirname/dirname should be an executable
        // unless dirname contains '~' for escaping namespace
        // e.g. dirname = vendor~cifs
        // then, executable will be pluginDir/dirname/cifs
        if f.IsDir() {
            execPath := path.Join(pluginDir, f.Name())
            plugins = append(plugins, &flexVolumePlugin{driverName: utilstrings.UnescapePluginName(f.Name()), execPath: execPath})
        }
    }
    return plugins
}
```

flexvolume 的详细分析请参考 [flex volume plugin 分析](flexvolume_plugin.md).

<h3 id='1.3.2'>### 初始化 volume plugins</h3>

kubelet 利用 `VolumePluginMgr` 来初始化和获取 volume plugin.

```
// pkg/kubelet/kubelet.go

// NewMainKubelet instantiates a new Kubelet object along with all the required internal modules.
// No initialization of Kubelet and its modules should happen here.
func NewMainKubelet(kubeCfg *componentconfig.KubeletConfiguration, kubeDeps *KubeletDeps, standaloneMode bool) (*Kubelet, error) {
    ...
    klet.volumePluginMgr, err =
        NewInitializedVolumePluginMgr(klet, kubeDeps.VolumePlugins)
    if err != nil {
        return nil, err
    }
    ...
}
```

`NewInitializedVolumePluginMgr` 函数中初始化所有的 volume plugin.

```
// pkg/kubelet/volume_host.go

// NewInitializedVolumePluginMgr returns a new instance of
// volume.VolumePluginMgr initialized with kubelets implementation of the
// volume.VolumeHost interface.
//
// kubelet - used by VolumeHost methods to expose kubelet specific parameters
// plugins - used to initialize volumePluginMgr
func NewInitializedVolumePluginMgr(
    kubelet *Kubelet,
    plugins []volume.VolumePlugin) (*volume.VolumePluginMgr, error) {
    kvh := &kubeletVolumeHost{
        kubelet:         kubelet,
        volumePluginMgr: volume.VolumePluginMgr{},
    }

    if err := kvh.volumePluginMgr.InitPlugins(plugins, kvh); err != nil {
        return nil, fmt.Errorf(
            "Could not initialize volume plugins for KubeletVolumePluginMgr: %v",
            err)
    }

    return &kvh.volumePluginMgr, nil
}
```

`InitPlugins` 负责调用每个 volume plugin 的 `Init` 函数进行初始化.

```
// pkg/volume/plugins.go

// InitPlugins initializes each plugin.  All plugins must have unique names.
// This must be called exactly once before any New* methods are called on any
// plugins.
func (pm *VolumePluginMgr) InitPlugins(plugins []VolumePlugin, host VolumeHost) error {
    pm.mutex.Lock()
    defer pm.mutex.Unlock()

    if pm.plugins == nil {
        pm.plugins = map[string]VolumePlugin{}
    }

    allErrs := []error{}
    for _, plugin := range plugins {
        name := plugin.GetPluginName()
        if errs := validation.IsQualifiedName(name); len(errs) != 0 {
            allErrs = append(allErrs, fmt.Errorf("volume plugin has invalid name: %q: %s", name, strings.Join(errs, ";")))
            continue
        }

        if _, found := pm.plugins[name]; found {
            allErrs = append(allErrs, fmt.Errorf("volume plugin %q was registered more than once", name))
            continue
        }
        err := plugin.Init(host)
        if err != nil {
            glog.Errorf("Failed to load volume plugin %s, error: %s", plugin, err.Error())
            allErrs = append(allErrs, err)
            continue
        }
        pm.plugins[name] = plugin
        glog.V(1).Infof("Loaded volume plugin %q", name)
    }
    return utilerrors.NewAggregate(allErrs)
}
```

<h2 id='1.4'>## Attach/Detach Controller 分析</h2>

<h3 id='1.4.1'>### 功能分析</h3>

Attach/Detach Controller 是在 1.3 版本中合入的, 为什么要引入这个 controller 呢? 原因主要有三个:

首先, 在之前的 kubernetes 设计中, kubelet 负责决定哪些 volume 要 attach 到该 kubelet 所在 node 或者从该 node 上 detach 出去. 因此, 一旦 kubelet 或者 node 宕掉了, 已经 attach 到该 node 的 volumes 仍然保持 attached 状态.

当一个 node 不可访问的时候 (可能是网络原因, kubelet crash 了, node 重启了等等), node controller 会把该 node 标记为 down 状态, 并删除所有调度该 node 的 pod. 这些 pod 随后被调度到其他 node 上. 这些需要 ReadWriteOnce volume (这些 volume 一次只能被 attach 到一个 node) 的 pod 将在新的 node 上启动失败, 因为这些 pod 所需要的 volume 现在仍然 attached 在原来的 node 上.

**注:**
```
只有实现了 Attacher interface 的 plugins (比如 GCE PD, AWS EBS 等) 才会与 attach/detach controller 一起工作. 集群中的任何一个 node 触发的 attach 操作都会在 attach/detach controller 上处理, 而 node 触发的 mount 操作只能在该 node 上处理. 因为像 RDB, ISCSI, NFS 等这些插件只实现了 Mounter 接口, 而且由 kubelet 来控制. kubelet 要等 attach/detach controller 将 volume device attach 到该 node 之后, 才会执行 mount 操作将 volume device mount 到 pod 上. 同样, 正常情况下, 只有 kubelet 从 pod 上 unmount 了 volume device, 并且该 node 上已经没有 pod 在使用该 volume device 了, attach/detach controller 才会把该 volume device 从 node 上 detach. 非正常情况下是指 kubelet 或者 node 宕掉了, pod 需要 rescheduled 到其他的 node 上, 所以 attach/detach controller 就直接把 volume device 从 node 上 detach.
```

此外, 在之前的设计中, kubelet 中决定是否一个 volume 应该被 attach 到该 node 的逻辑与决定是否一个 volume 应该从该 node detach 的逻辑是分开的而且完全独立的. 当一个 pod 被快速的创建, 删除和重新创建时, 就在 attach 和 detach 逻辑之间出现了 race condition, 从而导致了一些不确定的行为.

再次, 对许多类型的 volume 来说, 为了让 node 来触发 attach 和 detach 操作, node 通常需要来自云服务商 (cloud provider) 的更广泛的权限. 比如运行在 GCE 上的 kubernetes node 为了能发起 GCE PD attach/detach 操作就需要 compute-rw 权限范围.

所以 controller 主要实现如下目标:

- volume 的 attach 和 detach 逻辑从 node 的可用性中独立出来
    + 如果一个 node 或者 kubelet 宕掉了, 已经 attached 到该 node 的所有 volumes 都应该被 detached, 以便这些 volume 能被 attached 到其他 node 上去.
- 安全的云服务提供商证书
    + 因为 kubelet 负责触发 attach/detach 逻辑, 所以现在每个 node 都需要 (通常更广泛的) 权限, 而这些权限应该仅限于 master 节点. 比如 Google Compute Engine (GCE), 这就意味着 node 不再需要 computer-rw 权限范围.
- 提高 volume attach/detach 代码的稳定性
    + 之前的代码存在 race condition

有了上述背景之后, Attach/Detach Controller 的主要功能也就清晰了:

Attach/Detach Controller 主要负责集群中所有特定类型 (that volume type based on the node it is scheduled to, 我们后面统一称为`基于 node 的 volume 类型`) volume 的 attaching 和 detaching 工作. Attach/Detach Controller 将 watch pod 的调度和删除. 当一个新的 pod 被调度到 node 上的时候, 将为该 pod 使用的 volume 触发 attach 逻辑. 如果该 volume 类型为`基于 node 的 volume 类型`, 那么将触发该`基于 node 的 volume 类型`对应的 attach 逻辑, 比如 GCE PD 类型将触发 GCE PD attach 逻辑; 同样, 当一个 pod 被删除时, 将为该 pod 使用的 volume 触发 detach 逻辑, 如果该 volume 类型为`基于 node 的 volume 类型`, 那么将触发该`基于 node 的 volume 类型`对应的 detach 逻辑, 比如 GCE PD 类型将触发 GCE PD detach 逻辑. 如果该 volume 类型不属于`基于 node 的 volume 类型`, 那么其对应的 attach 和 detach 操作就是空的 (no-ops).

<h3 id='1.4.2'>### 关键代码分析</h3>

AttachDetachController 实例化代码如下:

```
// pkg/controller/volume/attachdetach/attach_detach_controller.go

// 从参数上看, NewAttachDetachController 关心的是 pod, node, pvc 和 pv.
// 这里只所有需要关心 pvc 和 pv, 是由于从 pod 中获取 volumeSpec 时, 有可能就是 pvc
// 所以, 这个 volumeSpec 就得来自 pv
// NewAttachDetachController returns a new instance of AttachDetachController.
func NewAttachDetachController(
    kubeClient clientset.Interface,
    podInformer coreinformers.PodInformer,
    nodeInformer coreinformers.NodeInformer,
    pvcInformer coreinformers.PersistentVolumeClaimInformer,
    pvInformer coreinformers.PersistentVolumeInformer,
    cloud cloudprovider.Interface,
    plugins []volume.VolumePlugin,
    disableReconciliationSync bool,
    reconcilerSyncDuration time.Duration) (AttachDetachController, error) {
    // TODO: The default resyncPeriod for shared informers is 12 hours, this is
    // unacceptable for the attach/detach controller. For example, if a pod is
    // skipped because the node it is scheduled to didn't set its annotation in
    // time, we don't want to have to wait 12hrs before processing the pod
    // again.
    // Luckily https://github.com/kubernetes/kubernetes/issues/23394 is being
    // worked on and will split resync in to resync and relist. Once that
    // happens the resync period can be set to something much faster (30
    // seconds).
    // If that issue is not resolved in time, then this controller will have to
    // consider some unappealing alternate options: use a non-shared informer
    // and set a faster resync period even if it causes relist, or requeue
    // dropped pods so they are continuously processed until it is accepted or
    // deleted (probably can't do this with sharedInformer), etc.
    adc := &attachDetachController{
        kubeClient:  kubeClient,
        pvcLister:   pvcInformer.Lister(),
        pvcsSynced:  pvcInformer.Informer().HasSynced,
        pvLister:    pvInformer.Lister(),
        pvsSynced:   pvInformer.Informer().HasSynced,
        podLister:   podInformer.Lister(),
        podsSynced:  podInformer.Informer().HasSynced,
        nodeLister:  nodeInformer.Lister(),
        nodesSynced: nodeInformer.Informer().HasSynced,
        cloud:       cloud,
    }

    // 初始化 volume plugins
    if err := adc.volumePluginMgr.InitPlugins(plugins, adc); err != nil {
        return nil, fmt.Errorf("Could not initialize volume plugins for Attach/Detach Controller: %+v", err)
    }
    ...
    // DesiredStateOfWorld 接口定义了一系列在 attach/detach controller
    // 期望的 cache 状态上进行的线程安全的操作
    // 该 cache 包含: nodes -> volumes -> pods
    adc.desiredStateOfWorld = cache.NewDesiredStateOfWorld(&adc.volumePluginMgr)
    // ActualStateOfWorld 接口定义了一系列在 attach/detach controller
    // 实际的 cache 状态上进行的线程安全的操作
    // 该 cache 包含: volumes -> nodes
    adc.actualStateOfWorld = cache.NewActualStateOfWorld(&adc.volumePluginMgr)
    // attacherDetacher 负责执行异步的 attach 和 detach 操作
    // 操作是通过 operationexecutor 接口封装的
    // operationexecutor 实际上会调用真正的 volume plugin 的代码
    adc.attacherDetacher =
        operationexecutor.NewOperationExecutor(operationexecutor.NewOperationGenerator(
            kubeClient,
            &adc.volumePluginMgr,
            recorder,
            false)) // flag for experimental binary check for volume mount
    // nodeStatusUpdater 负责更新 node object (API object)
    // 主要是将 attached 到该 node 的 volumes 持久化到 node object
    adc.nodeStatusUpdater = statusupdater.NewNodeStatusUpdater(
        kubeClient, nodeInformer.Lister(), adc.actualStateOfWorld)

    // Default these to values in options
    // reconciler 让 actualStateOfWorld 走向 desiredStateOfWorld
    adc.reconciler = reconciler.NewReconciler(
        reconcilerLoopPeriod,
        reconcilerMaxWaitForUnmountDuration,
        reconcilerSyncDuration,
        disableReconciliationSync,
        adc.desiredStateOfWorld,
        adc.actualStateOfWorld,
        adc.attacherDetacher,
        adc.nodeStatusUpdater)

    // desiredStateOfWorldPopulator 异步方式周期性运行统计当前 pods
    adc.desiredStateOfWorldPopulator = populator.NewDesiredStateOfWorldPopulator(
        desiredStateOfWorldPopulatorLoopSleepPeriod,
        desiredStateOfWorldPopulatorListPodsRetryDuration,
        podInformer.Lister(),
        adc.desiredStateOfWorld,
        &adc.volumePluginMgr,
        pvcInformer.Lister(),
        pvInformer.Lister())
    // 我们只关心 pod 和 node 的变化, 这里设置回调函数
    podInformer.Informer().AddEventHandler(kcache.ResourceEventHandlerFuncs{
        AddFunc:    adc.podAdd,
        UpdateFunc: adc.podUpdate,
        DeleteFunc: adc.podDelete,
    })

    nodeInformer.Informer().AddEventHandler(kcache.ResourceEventHandlerFuncs{
        AddFunc:    adc.nodeAdd,
        UpdateFunc: adc.nodeUpdate,
        DeleteFunc: adc.nodeDelete,
    })

    return adc, nil
}
```

AttachDetachController 接口比较简单, 只有两个方法:

```
// pkg/controller/volume/attachdetach/attach_detach_controller.go

// AttachDetachController defines the operations supported by this controller.
type AttachDetachController interface {
    Run(stopCh <-chan struct{})
    GetDesiredStateOfWorld() cache.DesiredStateOfWorld
}
```

我们看看 Run 方法的实现:

```
// pkg/controller/volume/attachdetach/attach_detach_controller.go

func (adc *attachDetachController) Run(stopCh <-chan struct{}) {
    defer runtime.HandleCrash()

    glog.Infof("Starting attach detach controller")
    defer glog.Infof("Shutting down attach detach controller")

    // 等待所有 informer 都 sync 好
    if !controller.WaitForCacheSync("attach detach", stopCh, adc.podsSynced, adc.nodesSynced, adc.pvcsSynced, adc.pvsSynced) {
        return
    }

    // 从现实角度遍历所有 node 和 node.Status.VolumesAttached
    // 更新 attached 的 volume
    // 将 attached 了 volume 的 node 添加到 DesiredStateOfWorld (表示 attached 
    // 了 volume 的 node 的理想状态是可以被 attach/detach controller 管理的)
    err := adc.populateActualStateOfWorld()
    if err != nil {
        glog.Errorf("Error populating the actual state of world: %v", err)
    }
    
    // 从理想角度遍历所有的 pod 和 podToAdd.Spec.Volumes
    // 将需要进行 attach 的 volume 和 volume 对应的 pod 添加到 DesiredStateOfWorld
    err = adc.populateDesiredStateOfWorld()
    if err != nil {
        glog.Errorf("Error populating the desired state of world: %v", err)
    }
    // reconciler 将 actualStateOfWorld 和 desiredStateOfWorld 进行对比
    // 首先, 确保该 detach 的 volume 就执行 detach 操作
    // 其次, 确保该 attach 的 volume 就执行 attach 操作
    // 最后, 更新 node object, 将 attached 到 node 的 volumes 持久化到 node object
    go adc.reconciler.Run(stopCh)
    go adc.desiredStateOfWorldPopulator.Run(stopCh)

    <-stopCh
}
```

下面我们看看 `adc.reconciler.Run` 代码:

```
// pkg/controller/volume/attachdetach/reconciler/reconciler.go

func (rc *reconciler) Run(stopCh <-chan struct{}) {
    wait.Until(rc.reconciliationLoopFunc(), rc.loopPeriod, stopCh)
}

// reconciliationLoopFunc this can be disabled via cli option disableReconciliation.
// It periodically checks whether the attached volumes from actual state
// are still attached to the node and update the status if they are not.
func (rc *reconciler) reconciliationLoopFunc() func() {
    return func() {

        rc.reconcile()

        if rc.disableReconciliationSync {
            glog.V(5).Info("Skipping reconciling attached volumes still attached since it is disabled via the command line.")
        } else if rc.syncDuration < time.Second {
            glog.V(5).Info("Skipping reconciling attached volumes still attached since it is set to less than one second via the command line.")
        } else if time.Since(rc.timeOfLastSync) > rc.syncDuration {
            // 周期性的与底层 storage system 去同步, 确保 node obj 中记录的 attached 
            // 的 volume 的状态的正确性
            glog.V(5).Info("Starting reconciling attached volumes still attached")
            rc.sync()
        }
    }
}

func (rc *reconciler) sync() {
    defer rc.updateSyncTime()
    rc.syncStates()
}

func (rc *reconciler) syncStates() {
    volumesPerNode := rc.actualStateOfWorld.GetAttachedVolumesPerNode()
    // 直接从底层的 storage system 去检查 volume 是否处于 attached 状态
    // 因为 node/kubelet 是不可靠的
    // 这里通过 operationexecutor 调用真正的 volume plugin 的代码去做检查
    // 如果发现该 volume device 已经不再 attach 到对应的 node 时, 
    // 更新 actualStateOfWorld 状态, 记录该 volume 已经 detached 了
    rc.attacherDetacher.VerifyVolumesAreAttached(volumesPerNode, rc.actualStateOfWorld)
}

func (rc *reconciler) reconcile() {
    // Detaches are triggered before attaches so that volumes referenced by
    // pods that are rescheduled to a different node are detached first.

    // 首先, 确保该 detach 的 volume 就执行 detach 操作
    // Ensure volumes that should be detached are detached.
    for _, attachedVolume := range rc.actualStateOfWorld.GetAttachedVolumes() {
        if !rc.desiredStateOfWorld.VolumeExists(
            attachedVolume.VolumeName, attachedVolume.NodeName) {

            // Don't even try to start an operation if there is already one running
            // This check must be done before we do any other checks, as otherwise the other checks
            // may pass while at the same time the volume leaves the pending state, resulting in
            // double detach attempts
            if rc.attacherDetacher.IsOperationPending(attachedVolume.VolumeName, "") {
                glog.V(10).Infof("Operation for volume %q is already running. Can't start detach for %q", attachedVolume.VolumeName, attachedVolume.NodeName)
                continue
            }

            // Set the detach request time
            elapsedTime, err := rc.actualStateOfWorld.SetDetachRequestTime(attachedVolume.VolumeName, attachedVolume.NodeName)
            if err != nil {
                glog.Errorf("Cannot trigger detach because it fails to set detach request time with error %v", err)
                continue
            }
            // Check whether timeout has reached the maximum waiting time
            timeout := elapsedTime > rc.maxWaitForUnmountDuration
            // Check whether volume is still mounted. Skip detach if it is still mounted unless timeout
            if attachedVolume.MountedByNode && !timeout {
                glog.V(12).Infof(attachedVolume.GenerateMsgDetailed("Cannot detach volume because it is still mounted", ""))
                continue
            }

            // Before triggering volume detach, mark volume as detached and update the node status
            // If it fails to update node status, skip detach volume
            err = rc.actualStateOfWorld.RemoveVolumeFromReportAsAttached(attachedVolume.VolumeName, attachedVolume.NodeName)
            if err != nil {
                glog.V(5).Infof("RemoveVolumeFromReportAsAttached failed while removing volume %q from node %q with: %v",
                    attachedVolume.VolumeName,
                    attachedVolume.NodeName,
                    err)
            }

            // Update Node Status to indicate volume is no longer safe to mount.
            err = rc.nodeStatusUpdater.UpdateNodeStatuses()
            if err != nil {
                // Skip detaching this volume if unable to update node status
                glog.Errorf(attachedVolume.GenerateErrorDetailed("UpdateNodeStatuses failed while attempting to report volume as attached", err).Error())
                continue
            }

            // Trigger detach volume which requires verifing safe to detach step
            // If timeout is true, skip verifySafeToDetach check
            glog.V(5).Infof(attachedVolume.GenerateMsgDetailed("Starting attacherDetacher.DetachVolume", ""))
            verifySafeToDetach := !timeout
            err = rc.attacherDetacher.DetachVolume(attachedVolume.AttachedVolume, verifySafeToDetach, rc.actualStateOfWorld)
            if err == nil {
                if !timeout {
                    glog.Infof(attachedVolume.GenerateMsgDetailed("attacherDetacher.DetachVolume started", ""))
                } else {
                    glog.Infof(attachedVolume.GenerateMsgDetailed("attacherDetacher.DetachVolume started", fmt.Sprintf("This volume is not safe to detach, but maxWaitForUnmountDuration %v expired, force detaching", rc.maxWaitForUnmountDuration)))
                }
            }
            if err != nil && !exponentialbackoff.IsExponentialBackoff(err) {
                // Ignore exponentialbackoff.IsExponentialBackoff errors, they are expected.
                // Log all other errors.
                glog.Errorf(attachedVolume.GenerateErrorDetailed("attacherDetacher.DetachVolume failed to start", err).Error())
            }
        }
    }

    // 其次, 确保该 attach 的 volume 就执行 attach 操作
    // Ensure volumes that should be attached are attached.
    for _, volumeToAttach := range rc.desiredStateOfWorld.GetVolumesToAttach() {
        if rc.actualStateOfWorld.VolumeNodeExists(
            volumeToAttach.VolumeName, volumeToAttach.NodeName) {
            // Volume/Node exists, touch it to reset detachRequestedTime
            glog.V(5).Infof(volumeToAttach.GenerateMsgDetailed("Volume attached--touching", ""))
            rc.actualStateOfWorld.ResetDetachRequestTime(volumeToAttach.VolumeName, volumeToAttach.NodeName)
        } else {
            // Don't even try to start an operation if there is already one running
            if rc.attacherDetacher.IsOperationPending(volumeToAttach.VolumeName, "") {
                glog.V(10).Infof("Operation for volume %q is already running. Can't start attach for %q", volumeToAttach.VolumeName, volumeToAttach.NodeName)
                continue
            }

            if rc.isMultiAttachForbidden(volumeToAttach.VolumeSpec) {
                nodes := rc.actualStateOfWorld.GetNodesForVolume(volumeToAttach.VolumeName)
                if len(nodes) > 0 {
                    glog.V(4).Infof("Volume %q is already exclusively attached to node %q and can't be attached to %q", volumeToAttach.VolumeName, nodes, volumeToAttach.NodeName)
                    continue
                }
            }

            // Volume/Node doesn't exist, spawn a goroutine to attach it
            glog.V(5).Infof(volumeToAttach.GenerateMsgDetailed("Starting attacherDetacher.AttachVolume", ""))
            err := rc.attacherDetacher.AttachVolume(volumeToAttach.VolumeToAttach, rc.actualStateOfWorld)
            if err == nil {
                glog.Infof(volumeToAttach.GenerateMsgDetailed("attacherDetacher.AttachVolume started", ""))
            }
            if err != nil && !exponentialbackoff.IsExponentialBackoff(err) {
                // Ignore exponentialbackoff.IsExponentialBackoff errors, they are expected.
                // Log all other errors.
                glog.Errorf(volumeToAttach.GenerateErrorDetailed("attacherDetacher.AttachVolume failed to start", err).Error())
            }
        }
    }

    // 最后, 更新 node object, 将 attached 到 node 的 volumes 持久化到 node object
    // Update Node Status
    err := rc.nodeStatusUpdater.UpdateNodeStatuses()
    if err != nil {
        glog.Infof("UpdateNodeStatuses failed with: %v", err)
    }
}
```

<h2 id='1.5'>## pv Controller 分析</h2>
// TODO

<h2 id='1.6'>## kubelet volumemanager 分析</h2>
// TODO

<h2 id='1.7'>## operationexecutor 分析</h2>
// TODO

rbd 没有实现 attachable interface，所以 volume attach 操作不是由 attach detach controller 来做的，而是由 kubelet -> rbd plugin -> diskSetUp 来做的

<h1 id='2'># References</h2>

1. [volumes proposal](https://github.com/kubernetes/community/blob/master/contributors/design-proposals/volumes.md)
2. [Flexvolume proposal](https://github.com/kubernetes/community/blob/master/contributors/devel/flexvolume.md)
3. [An Introduction to Kubernetes FlexVolumes](http://leebriggs.co.uk/blog/2017/03/12/kubernetes-flexvolumes.html)
4. [Flexvolume example](https://github.com/kubernetes/kubernetes/tree/master/examples/volumes/flexvolume)
5. [volume provisioning proposal](https://github.com/kubernetes/community/blob/master/contributors/design-proposals/volume-provisioning.md)
6. [volume select proposal](https://github.com/kubernetes/community/blob/master/contributors/design-proposals/volume-selectors.md)
7. [Attach/Detach Controller proposal](https://github.com/kubernetes/kubernetes/issues/20262)
