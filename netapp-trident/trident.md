<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [netapp trident 源码分析](#netapp-trident-%E6%BA%90%E7%A0%81%E5%88%86%E6%9E%90)
  - [目录结构](#%E7%9B%AE%E5%BD%95%E7%BB%93%E6%9E%84)
  - [main.go](#maingo)
  - [orchestrator_core.go](#orchestrator_corego)
  - [kubernetes/plugin.go](#kubernetesplugingo)
  - [kubernetes/volumes.go](#kubernetesvolumesgo)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# netapp trident 源码分析

## 目录结构

trident 的目录比较多，但是主要看如下几个代码文件就能把 trident netapp nas 的整体代码看懂：

```
Netapp/trident
    │
    ├── config
    │   └── config.go
    ├── core
    │   └── orchestrator_core.go
    ├── frontend    // which frontend does trident serve for
    │   ├── kubernetes  // trident serves for kubernetes frontend
    │   │   ├── config.go
    │   │   ├── plugin.go
    │   │   └── volumes.go
    │   ├── rest    // trident supplies rest api server for orchestrator state
    │   │   └── ...
    │   └── frontend.go
    ├── k8s_client
    │   └── k8s_client.go
    ├── persistent_store    // persisting orchestrator state
    │   └── etcdv3.go
    ├── storage // which backend does trident use
    │   ├── ontap // trident uses ontap as backend
    │   │   ├── ontap_common.go
    │   │   └── ontap_nas.go
    │   ├── backend.go
    │   ├── config.go
    │   └── volume.go
    ├── storage_class   // corresponds with k8s storage class
    │   ├── config.go
    │   ├── storage_class.go
    │   └── types.go
    └── main.go
```

## main.go

```go
var (
    // Logging
    debug    = flag.Bool("debug", false, "Enable debugging output")
    logLevel = flag.String("log_level", "info", "Logging level (debug, info, warn, error, fatal)")

    // Kubernetes
    k8sAPIServer = flag.String("k8s_api_server", "", "Kubernetes API server "+
        "address to enable dynamic storage provisioning for Kubernetes.")
    k8sConfigPath = flag.String("k8s_config_path", "", "Path to KubeConfig file.")
    k8sPod        = flag.Bool("k8s_pod", false, "Enables dynamic storage provisioning "+
        "for Kubernetes if running in a pod.")

    // Docker
    driverName = flag.String("volume_driver", "netapp", "Register as a Docker "+
        "volume plugin with this driver name")
    driverPort = flag.String("driver_port", "", "Listen on this port instead of using a "+
        "Unix domain socket")
    configPath = flag.String("config", "", "Path to configuration file(s)")

    // Persistence
    etcdV2 = flag.String("etcd_v2", "", "etcd server (v2 API) for "+
        "persisting orchestrator state (e.g., -etcd_v2=http://127.0.0.1:8001)")
    etcdV3 = flag.String("etcd_v3", "", "etcd server (v3 API) for "+
        "persisting orchestrator state (e.g., -etcd_v3=http://127.0.0.1:8001)")
    etcdV3Cert = flag.String("etcd_v3_cert", "/root/certs/etcd-client.crt",
        "etcdV3 client certificate")
    etcdV3CACert = flag.String("etcd_v3_cacert", "/root/certs/etcd-client-ca.crt",
        "etcdV3 client CA certificate")
    etcdV3Key = flag.String("etcd_v3_key", "/root/certs/etcd-client.key",
        "etcdV3 client private key")
    useInMemory = flag.Bool("no_persistence", false, "Does not persist "+
        "any metadata.  WILL LOSE TRACK OF VOLUMES ON REBOOT/CRASH.")
    usePassthrough = flag.Bool("passthrough", false, "Uses the storage backends "+
        "as the source of truth.  No data is stored anywhere else.")

    // REST interface
    address    = flag.String("address", "localhost", "Storage orchestrator API address")
    port       = flag.String("port", "8000", "Storage orchestrator API port")
    enableRest = flag.Bool("rest", true, "Enable REST interface")

    storeClient      persistent_store.Client
    enableKubernetes bool
    enableDocker     bool
)

func main() {
    frontends := make([]frontend.FrontendPlugin, 0)
    orchestrator := core.NewTridentOrchestrator(storeClient)
    // Create Kubernetes *or* Docker frontend
    if enableKubernetes {

        var kubernetesFrontend frontend.FrontendPlugin

        if *k8sAPIServer != "" {
            kubernetesFrontend, err = kubernetes.NewPlugin(orchestrator, *k8sAPIServer, *k8sConfigPath)
        } else {
            kubernetesFrontend, err = kubernetes.NewPluginInCluster(orchestrator)
        }
        orchestrator.AddFrontend(kubernetesFrontend)
        frontends = append(frontends, kubernetesFrontend)

    } else if enableDocker {

    }

    // Create REST frontend
    if *enableRest {
        if *port == "" {
            log.Warning("REST interface will not be available (port not specified).")
        } else {
            restServer := rest.NewAPIServer(orchestrator, *address, *port)
            frontends = append(frontends, restServer)
            log.WithFields(log.Fields{"name": "REST"}).Info("Added frontend.")
        }
    }

    // Bootstrap the orchestrator and start its frontends
    if err = orchestrator.Bootstrap(); err != nil {
        log.Fatal(err.Error())
    }
    for _, f := range frontends {
        f.Activate()
    }

    // Register and wait for a shutdown signal
    c := make(chan os.Signal, 1)
    signal.Notify(c, os.Interrupt, syscall.SIGTERM)
    <-c
    log.Info("Shutting down.")
    for _, f := range frontends {
        f.Deactivate()
    }
    storeClient.Stop()
}
```

## orchestrator_core.go

```go
type tridentOrchestrator struct {
    backends       map[string]*storage.StorageBackend
    volumes        map[string]*storage.Volume
    frontends      map[string]frontend.FrontendPlugin
    mutex          *sync.Mutex
    storageClasses map[string]*storage_class.StorageClass
    storeClient    persistent_store.Client
    bootstrapped   bool
}

// returns a storage orchestrator instance
func NewTridentOrchestrator(client persistent_store.Client) *tridentOrchestrator {
    orchestrator := tridentOrchestrator{
        backends:       make(map[string]*storage.StorageBackend),
        volumes:        make(map[string]*storage.Volume),
        frontends:      make(map[string]frontend.FrontendPlugin),
        storageClasses: make(map[string]*storage_class.StorageClass),
        mutex:          &sync.Mutex{},
        storeClient:    client,
        bootstrapped:   false,
    }
    return &orchestrator
}


func (o *tridentOrchestrator) Bootstrap() error {
    var err error = nil
    dvp.DefaultStoragePrefix = config.OrchestratorName
    // backend driver
    dvp.ExtendedDriverVersion = config.OrchestratorName + "-" + config.OrchestratorVersion.String()
    if kubeFrontend, found := o.frontends["kubernetes"]; found {
        dvp.ExtendedDriverVersion =
            dvp.ExtendedDriverVersion + " " + kubeFrontend.Version()
    }

    // Bootstrap state from persistent store
    if err = o.bootstrap(); err != nil {
        errMsg := fmt.Sprintf("Failed during bootstrapping: %s",
            err.Error())
        return fmt.Errorf(errMsg)
    }
    o.bootstrapped = true
    log.Infof("%s bootstrapped successfully.", config.OrchestratorName)
    return err
}

func (o *tridentOrchestrator) bootstrapBackends() error {
    // add existing storage backends
    persistentBackends, err := o.storeClient.GetBackends()
    for _, b := range persistentBackends {
        newBackendExternal, err := o.AddStorageBackend(serializedConfig)
    }
    return nil
}

func (o *tridentOrchestrator) bootstrapStorageClasses() error {
    // add existing storage classes
    persistentStorageClasses, err := o.storeClient.GetStorageClasses()
    for _, psc := range persistentStorageClasses {
        o.storageClasses[sc.GetName()] = sc
        for _, b := range o.backends {
            sc.CheckAndAddBackend(b)
        }
    }
    return nil
}

func (o *tridentOrchestrator) bootstrapVolumes() error {
    // add exiesting volumes
    volumes, err := o.storeClient.GetVolumes()
    for _, v := range volumes {
        backend, ok = o.backends[v.Backend]
        storagePool, ok := backend.Storage[v.Pool]
        vol := storage.NewVolume(v.Config, backend, storagePool)
        vol.Pool.AddVolume(vol, true)
        o.volumes[vol.Config.Name] = vol
    }
    return nil
}

func (o *tridentOrchestrator) bootstrap() error {
    type bootstrapFunc func() error
    for _, f := range []bootstrapFunc{o.bootstrapBackends,
        o.bootstrapStorageClasses, o.bootstrapVolumes, o.bootstrapVolTxns} {
        err := f()
    }

    for backendName, backend := range o.backends {
        if !backend.Online && !backend.HasVolumes() {
            delete(o.backends, backendName)
            err := o.storeClient.DeleteBackend(backend)
            if err != nil {
                return fmt.Errorf("Failed to delete empty offline backend %s:"+
                    "%v", backendName, err)
            }
        }
    }

    return nil
}

func (o *tridentOrchestrator) AddFrontend(f frontend.FrontendPlugin) {
    name := f.GetName()
    if _, ok := o.frontends[name]; ok {
        return
    }
    o.frontends[name] = f
}

func (o *tridentOrchestrator) AddStorageBackend(configJSON string) (
    *storage.StorageBackendExternal, error) {
    storageBackend, err := factory.NewStorageBackendForConfig(configJSON)

    newBackend := true
    originalBackend, ok := o.backends[storageBackend.Name]
    if ok {
        newBackend = false
        if err = o.validateBackendUpdate(originalBackend, storageBackend); err != nil {
            return nil, err
        }
    }

    if err = o.updateBackendOnPersistentStore(storageBackend, newBackend); err != nil {
        return nil, err
    }
    o.backends[storageBackend.Name] = storageBackend

    classes := make([]string, 0, len(o.storageClasses))
    for _, storageClass := range o.storageClasses {
        if !newBackend {
            storageClass.RemovePoolsForBackend(originalBackend)
        }
        if added := storageClass.CheckAndAddBackend(storageBackend); added > 0 {
            classes = append(classes, storageClass.GetName())
        }
    }

    return storageBackend.ConstructExternal(), nil
}

func (o *tridentOrchestrator) AddVolume(volumeConfig *storage.VolumeConfig) (
    externalVol *storage.VolumeExternal, err error) {
    var (
        backend *storage.StorageBackend
        vol     *storage.Volume
    )

    if _, ok := o.volumes[volumeConfig.Name]; ok {
        return nil, fmt.Errorf("Volume %s already exists.", volumeConfig.Name)
    }
    volumeConfig.Version = config.OrchestratorAPIVersion

    storageClass, ok := o.storageClasses[volumeConfig.StorageClass]
    protocol := volumeConfig.Protocol
    if protocol == config.ProtocolAny {
        protocol = o.getProtocol(volumeConfig.AccessMode)
    }
    pools := storageClass.GetStoragePoolsForProtocol(volumeConfig.Protocol)

    // Choose a pool at random.
    for _, num := range rand.Perm(len(pools)) {
        backend = pools[num].Backend
        vol, err = backend.AddVolume(volumeConfig, pools[num], storageClass.GetAttributes())
        if vol != nil && err == nil {
            if vol.Config.Protocol == config.ProtocolAny {
                vol.Config.Protocol = backend.GetProtocol()
            }
            err = o.storeClient.AddVolume(vol)
            if err != nil {
                return nil, err
            }
            o.volumes[volumeConfig.Name] = vol
            externalVol = vol.ConstructExternal()
            return externalVol, nil
        } else if err != nil {
            
        }
    }

    return nil, err
}

func (o *tridentOrchestrator) deleteVolume(volumeName string) error {
    volume := o.volumes[volumeName]

    // Note that this call will only return an error if the backend actually
    // fails to delete the volume.  If the volume does not exist on the backend,
    // the nDVP will not return an error.  Thus, we're fine.
    if err := volume.Backend.RemoveVolume(volume); err != nil {
    }
    // Ignore failures to find the volume being deleted, as this may be called
    // during recovery of a volume that has already been deleted from etcd.
    // During normal operation, checks on whether the volume is present in the
    // volume map should suffice to prevent deletion of non-existent volumes.
    if err := o.storeClient.DeleteVolumeIgnoreNotFound(volume); err != nil {
    }
    delete(o.volumes, volumeName)
    return nil
}

func (o *tridentOrchestrator) DeleteVolume(volumeName string) (found bool, err error) {
    volume, ok := o.volumes[volumeName]
    if err = o.deleteVolume(volumeName); err != nil {
    }
    return true, nil
}

// AttachVolume mounts a volume to the local host.  It ensures the mount point exists,
// and it calls the underlying storage driver to perform the attach operation as appropriate
// for the protocol and storage controller type.
func (o *tridentOrchestrator) AttachVolume(volumeName, mountpoint string, options map[string]string) error {

    volume, ok := o.volumes[volumeName]

    // Ensure mount point exists and is a directory
    fileInfo, err := os.Lstat(mountpoint)

    // Check if volume is already mounted
    dfOutput, dfOuputErr := dvp_utils.GetDFOutput()

    return volume.Backend.Driver.Attach(volume.Config.InternalName, mountpoint, options)
}

func (o *tridentOrchestrator) DetachVolume(volumeName, mountpoint string) error {
    volume, ok := o.volumes[volumeName]

    // Check if the mount point exists, so we know that it's attached and must be cleaned up
    _, err := os.Stat(mountpoint)

    // Unmount the volume
    err = volume.Backend.Driver.Detach(volume.Config.InternalName, mountpoint)

    // Best effort removal of the mount point
    os.Remove(mountpoint)
    return nil
}

func (o *tridentOrchestrator) AddStorageClass(scConfig *storage_class.Config) (*storage_class.StorageClassExternal, error) {
    o.mutex.Lock()
    sc := storage_class.New(scConfig)
    err := o.storeClient.AddStorageClass(sc)
    o.storageClasses[sc.GetName()] = sc
    added := 0
    for _, backend := range o.backends {
        added += sc.CheckAndAddBackend(backend)
    }
    return sc.ConstructExternal(), nil
}

func (o *tridentOrchestrator) DeleteStorageClass(scName string) (bool, error) {
    sc, found := o.storageClasses[scName]
    // Note that we don't need a tranasaction here.  If this crashes prior
    // to successful deletion, the storage class will be reloaded upon reboot
    // automatically, which is consistent with the method never having returned
    // successfully.
    err := o.storeClient.DeleteStorageClass(sc)
    if err != nil {
        return found, err
    }
    delete(o.storageClasses, scName)
    for _, storagePool := range sc.GetStoragePoolsForProtocol(config.ProtocolAny) {
        storagePool.RemoveStorageClass(scName)
    }
    return found, nil
}
```

## kubernetes/plugin.go

```go
// This object captures relevant fields in the storage class that are needed
// during PV creation.
type StorageClassSummary struct {
    Parameters                    map[string]string
    MountOptions                  []string
    PersistentVolumeReclaimPolicy *v1.PersistentVolumeReclaimPolicy
}

type KubernetesPlugin struct {
    orchestrator             core.Orchestrator
    kubeClient               kubernetes.Interface
    getNamespacedKubeClient  func(*rest.Config, string) (k8s_client.Interface, error)
    kubeConfig               rest.Config
    eventRecorder            record.EventRecorder
    claimController          cache.Controller
    claimControllerStopChan  chan struct{}
    claimSource              cache.ListerWatcher
    volumeController         cache.Controller
    volumeControllerStopChan chan struct{}
    volumeSource             cache.ListerWatcher
    classController          cache.Controller
    classControllerStopChan  chan struct{}
    classSource              cache.ListerWatcher
    mutex                    *sync.Mutex
    pendingClaimMatchMap     map[string]*v1.PersistentVolume
    kubernetesVersion        *k8s_version.Info
    defaultStorageClasses    map[string]bool
    storageClassCache        map[string]*StorageClassSummary
}

func NewPlugin(o core.Orchestrator, apiServerIP, kubeConfigPath string) (*KubernetesPlugin, error) {
    kubeConfig, err := clientcmd.BuildConfigFromFlags(apiServerIP, kubeConfigPath)
    if err != nil {
        return nil, err
    }
    return newKubernetesPlugin(o, kubeConfig)
}

func NewPluginInCluster(o core.Orchestrator) (*KubernetesPlugin, error) {
    kubeConfig, err := rest.InClusterConfig()
    if err != nil {
        return nil, err
    }
    return newKubernetesPlugin(o, kubeConfig)
}

func newKubernetesPlugin(orchestrator core.Orchestrator, kubeConfig *rest.Config) (*KubernetesPlugin, error) {
    kubeClient, err := kubernetes.NewForConfig(kubeConfig)

    ret := &KubernetesPlugin{
        orchestrator:             orchestrator,
        kubeClient:               kubeClient,
        getNamespacedKubeClient:  k8s_client.NewKubeClient,
        kubeConfig:               *kubeConfig,
        claimControllerStopChan:  make(chan struct{}),
        volumeControllerStopChan: make(chan struct{}),
        classControllerStopChan:  make(chan struct{}),
        mutex:                 &sync.Mutex{},
        pendingClaimMatchMap:  make(map[string]*v1.PersistentVolume),
        defaultStorageClasses: make(map[string]bool, 1),
        storageClassCache:     make(map[string]*StorageClassSummary),
    }

    broadcaster := record.NewBroadcaster()
    broadcaster.StartRecordingToSink(
        &core_v1.EventSinkImpl{
            Interface: kubeClient.Core().Events(""),
        })
    ret.eventRecorder = broadcaster.NewRecorder(runtime.NewScheme(),
        v1.EventSource{Component: AnnOrchestrator})

    // Setting up a watch for PVCs
    ret.claimSource = &cache.ListWatch{
        ListFunc: func(options metav1.ListOptions) (runtime.Object, error) {
            return kubeClient.Core().PersistentVolumeClaims(
                v1.NamespaceAll).List(options)
        },
        WatchFunc: func(options metav1.ListOptions) (watch.Interface, error) {
            return kubeClient.Core().PersistentVolumeClaims(
                v1.NamespaceAll).Watch(options)
        },
    }
    _, ret.claimController = cache.NewInformer(
        ret.claimSource,
        &v1.PersistentVolumeClaim{},
        KubernetesSyncPeriod,
        cache.ResourceEventHandlerFuncs{
            AddFunc:    ret.addClaim,
            UpdateFunc: ret.updateClaim,
            DeleteFunc: ret.deleteClaim,
        },
    )

    // Setting up a watch for PVs
    ret.volumeSource = &cache.ListWatch{
        ListFunc: func(options metav1.ListOptions) (runtime.Object, error) {
            return kubeClient.Core().PersistentVolumes().List(options)
        },
        WatchFunc: func(options metav1.ListOptions) (watch.Interface, error) {
            return kubeClient.Core().PersistentVolumes().Watch(options)
        },
    }
    _, ret.volumeController = cache.NewInformer(
        ret.volumeSource,
        &v1.PersistentVolume{},
        KubernetesSyncPeriod,
        cache.ResourceEventHandlerFuncs{
            AddFunc:    ret.addVolume,
            UpdateFunc: ret.updateVolume,
            DeleteFunc: ret.deleteVolume,
        },
    )

    // Setting up a watch for storage classes
    switch {
    case kubeVersion.AtLeast(k8s_util_version.MustParseSemantic("v1.6.0")):
        ret.classSource = &cache.ListWatch{
            ListFunc: func(options metav1.ListOptions) (runtime.Object, error) {
                return kubeClient.StorageV1().StorageClasses().List(options)
            },
            WatchFunc: func(options metav1.ListOptions) (watch.Interface, error) {
                return kubeClient.StorageV1().StorageClasses().Watch(options)
            },
        }
        _, ret.classController = cache.NewInformer(
            ret.classSource,
            &k8s_storage_v1.StorageClass{},
            KubernetesSyncPeriod,
            cache.ResourceEventHandlerFuncs{
                AddFunc:    ret.addClass,
                UpdateFunc: ret.updateClass,
                DeleteFunc: ret.deleteClass,
            },
        )
    }
    return ret, nil
}

func (p *KubernetesPlugin) Activate() error {
    go p.claimController.Run(p.claimControllerStopChan)
    go p.volumeController.Run(p.volumeControllerStopChan)
    go p.classController.Run(p.classControllerStopChan)
    return nil
}

func (p *KubernetesPlugin) Deactivate() error {
    close(p.claimControllerStopChan)
    close(p.volumeControllerStopChan)
    close(p.classControllerStopChan)
    return nil
}

func getUniqueClaimName(claim *v1.PersistentVolumeClaim) string {
    id := string(claim.UID)
    r := strings.NewReplacer("-", "", "_", "", " ", "", ",", "")
    id = r.Replace(id)
    if len(id) > 5 {
        id = id[:5]
    }
    return fmt.Sprintf("%s-%s-%s", claim.Namespace, claim.Name, id)
}

func (p *KubernetesPlugin) addClaim(obj interface{}) {
    claim, ok := obj.(*v1.PersistentVolumeClaim)
    if !ok {
        log.Panicf("Kubernetes frontend expected PVC; handler got %v", obj)
    }
    p.processClaim(claim, "add")
}

func (p *KubernetesPlugin) updateClaim(oldObj, newObj interface{}) {
    claim, ok := newObj.(*v1.PersistentVolumeClaim)
    if !ok {
        log.Panicf("Kubernetes frontend expected PVC; handler got %v", newObj)
    }
    p.processClaim(claim, "update")
}

func (p *KubernetesPlugin) deleteClaim(obj interface{}) {
    claim, ok := obj.(*v1.PersistentVolumeClaim)
    if !ok {
        log.Panicf("Kubernetes frontend expected PVC; handler got %v", obj)
    }
    p.processClaim(claim, "delete")
}

func (p *KubernetesPlugin) processClaim(
    claim *v1.PersistentVolumeClaim,
    eventType string,
) {
    // Validating the claim
    size, ok := claim.Spec.Resources.Requests[v1.ResourceStorage]

    // It's a valid PVC.
    switch eventType {
    case "delete":
        p.processDeletedClaim(claim)
        return
    case "add":
    case "update":
    default:
        return
    }

    // Treating add and update events similarly.
    // Making decisions based on a claim's phase, similar to k8s' persistent volume controller.
    switch claim.Status.Phase {
    case v1.ClaimBound:
        p.processBoundClaim(claim)
        return
    case v1.ClaimLost:
        p.processLostClaim(claim)
        return
    case v1.ClaimPending:
        // As of Kubernetes 1.6, selector and storage class are mutually exclusive.
        if claim.Spec.Selector != nil {
            message := "Kubernetes frontend ignores PVCs with label selectors!"
            p.updateClaimWithEvent(claim, v1.EventTypeWarning, "IgnoredClaim",
                message)
            return
        }
        p.processPendingClaim(claim)
    default:
    }
}

// processBoundClaim validates whether a Trident-created PV got bound to the intended PVC.
func (p *KubernetesPlugin) processBoundClaim(claim *v1.PersistentVolumeClaim) {
    orchestratorClaimName := getUniqueClaimName(claim)
    p.mutex.Lock()
    pv, ok := p.pendingClaimMatchMap[orchestratorClaimName]
    p.mutex.Unlock()

    // If the bound volume name doesn't match the volume we provisioned,
    // we need to delete the PV and its backing volume, since something
    // else (e.g., an admin-provisioned volume or another provisioner)
    // was able to take care of the PVC.
    // Names are unique for a given instance in time (volumes aren't namespaced,
    // so namespace is a nonissue), so we only need to check whether the
    // name matches.
    boundVolumeName := claim.Spec.VolumeName
    if pv.Name != boundVolumeName {
        err := p.deleteVolumeAndPV(pv)
        return
    }
    // The names match, so the PVC is successfully bound to the provisioned PV.
    return
}

func (p *KubernetesPlugin) processLostClaim(claim *v1.PersistentVolumeClaim) {
    volName := getUniqueClaimName(claim)

    // A PVC is in the "Lost" phase when the corresponding PV is deleted.
    // Check whether we need to recycle the claim and the corresponding volume.
    if getClaimReclaimPolicy(claim) == string(v1.PersistentVolumeReclaimRetain) {
        return
    }

    _, err := p.orchestrator.DeleteVolume(volName)
    return
}

func (p *KubernetesPlugin) processDeletedClaim(claim *v1.PersistentVolumeClaim) {
    // No major action needs to be taken as deleting a claim would result in
    // the corresponding PV to end up in the "Released" phase, which gets
    // handled by processUpdatedVolume.
    // Remove the pending claim, if present.
    p.mutex.Lock()
    delete(p.pendingClaimMatchMap, getUniqueClaimName(claim))
    p.mutex.Unlock()
}

// processPendingClaim processes PVCs in the pending phase.
func (p *KubernetesPlugin) processPendingClaim(claim *v1.PersistentVolumeClaim) {
    orchestratorClaimName := getUniqueClaimName(claim)
    p.mutex.Lock()

    // Check whether we have already provisioned a PV for this claim
    if pv, ok := p.pendingClaimMatchMap[orchestratorClaimName]; ok {
        // If there's an entry for this claim in the pending claim match
        // map, we need to see if the volume that we allocated can actually
        // fit the (now modified) specs for the claim.  Note that by checking
        // whether the volume was bound before we get here, we're assuming
        // users don't alter the specs on their PVC after it's been bound.
        // Note that as of Kubernetes 1.5, this case isn't possible, as PVC
        // specs are immutable.  This remains in case Kubernetes allows PVC
        // modification again.
        if canPVMatchWithPVC(pv, claim) {
            p.mutex.Unlock()
            return
        }
        // Otherwise, we need to delete the old volume and allocate a new one
        if err := p.deleteVolumeAndPV(pv); err != nil {
        }
        delete(p.pendingClaimMatchMap, orchestratorClaimName)
    }
    p.mutex.Unlock()

    // We need to provision a new volume for this claim.
    pv, err := p.createVolumeAndPV(orchestratorClaimName, claim)

    p.mutex.Lock()
    p.pendingClaimMatchMap[orchestratorClaimName] = pv
    p.mutex.Unlock()
    message := "Kubernetes frontend provisioned a volume and a PV for the PVC."
    p.updateClaimWithEvent(claim, v1.EventTypeNormal,
        "ProvisioningSuccess", message)
}

func (p *KubernetesPlugin) createVolumeAndPV(uniqueName string,
    claim *v1.PersistentVolumeClaim,
) (pv *v1.PersistentVolume, err error) {
    var (
        nfsSource          *v1.NFSVolumeSource
        iscsiSource        *v1.ISCSIVolumeSource
        vol                *storage.VolumeExternal
        storageClassParams map[string]string
    )

    size, _ := claim.Spec.Resources.Requests[v1.ResourceStorage]
    accessModes := claim.Spec.AccessModes
    annotations := claim.Annotations
    storageClass := GetPersistentVolumeClaimClass(claim)
    if storageClassSummary, found := p.storageClassCache[storageClass]; found {
        storageClassParams = storageClassSummary.Parameters
    }

    // TODO: A quick way to support v1 storage classes before changing unit tests
    if _, found := annotations[AnnClass]; !found {
        if annotations == nil {
            annotations = make(map[string]string)
        }
        annotations[AnnClass] = GetPersistentVolumeClaimClass(claim)
    }

    // Set the file system type based on the value in the storage class
    if _, found := annotations[AnnFileSystem]; !found && storageClassParams != nil {
        if fsType, found := storageClassParams[K8sFsType]; found {
            annotations[AnnFileSystem] = fsType
        }
    }

    k8sClient, err := p.getNamespacedKubeClient(&p.kubeConfig, claim.Namespace)

    // Create the volume configuration object
    volConfig := getVolumeConfig(accessModes, uniqueName, size, annotations)
    if volConfig.CloneSourceVolume == "" {
        vol, err = p.orchestrator.AddVolume(volConfig)
    } else {
        // cloning an existing PVC
    }

    claimRef := v1.ObjectReference{
        Namespace: claim.Namespace,
        Name:      claim.Name,
        UID:       claim.UID,
    }
    pv = &v1.PersistentVolume{
        TypeMeta: metav1.TypeMeta{
            Kind:       "PersistentVolume",
            APIVersion: "v1",
        },
        ObjectMeta: metav1.ObjectMeta{
            Name: uniqueName,
            Annotations: map[string]string{
                AnnClass:                  GetPersistentVolumeClaimClass(claim),
                AnnDynamicallyProvisioned: AnnOrchestrator,
            },
        },
        Spec: v1.PersistentVolumeSpec{
            AccessModes: accessModes,
            Capacity:    v1.ResourceList{v1.ResourceStorage: size},
            ClaimRef:    &claimRef,
            // Default policy is "Delete".
            PersistentVolumeReclaimPolicy: v1.PersistentVolumeReclaimDelete,
        },
    }

    kubeVersion, _ := ValidateKubeVersion(p.kubernetesVersion)
    switch {
    //TODO: Set StorageClassName when we create the PV once the support for
    //      k8s 1.5 is dropped.
    case kubeVersion.AtLeast(k8s_util_version.MustParseSemantic("v1.8.0")):
        pv.Spec.StorageClassName = GetPersistentVolumeClaimClass(claim)
        // Apply Storage Class mount options and reclaim policy
        pv.Spec.MountOptions = p.storageClassCache[storageClass].MountOptions
        pv.Spec.PersistentVolumeReclaimPolicy =
            *p.storageClassCache[storageClass].PersistentVolumeReclaimPolicy
    case kubeVersion.AtLeast(k8s_util_version.MustParseSemantic("v1.6.0")):
        pv.Spec.StorageClassName = GetPersistentVolumeClaimClass(claim)
    }

    // PVC annotation takes precedence over the storage class field
    if getClaimReclaimPolicy(claim) ==
        string(v1.PersistentVolumeReclaimRetain) {
        // Extra flexibility in our implementation.
        pv.Spec.PersistentVolumeReclaimPolicy =
            v1.PersistentVolumeReclaimRetain
    }

    driverType := p.orchestrator.GetDriverTypeForVolume(vol)
    switch {
    case driverType == dvp.SolidfireSANStorageDriverName ||
        driverType == dvp.OntapSANStorageDriverName ||
        driverType == dvp.EseriesIscsiStorageDriverName:
        iscsiSource, err = CreateISCSIVolumeSource(k8sClient, kubeVersion, vol)
        if err != nil {
            return
        }
        pv.Spec.ISCSI = iscsiSource
    case driverType == dvp.OntapNASStorageDriverName ||
        driverType == dvp.OntapNASQtreeStorageDriverName:
        nfsSource = CreateNFSVolumeSource(vol)
        // nfsSource contains a server and a path
        // kubelet uses pv.Spec.NFS to mount a nfs volume into a pod
        pv.Spec.NFS = nfsSource
    case driverType == fake.FakeStorageDriverName:
        if vol.Config.Protocol == config.File {
            nfsSource = CreateNFSVolumeSource(vol)
            pv.Spec.NFS = nfsSource
        } else if vol.Config.Protocol == config.Block {
            iscsiSource, err = CreateISCSIVolumeSource(k8sClient, kubeVersion, vol)
            if err != nil {
                return
            }
            pv.Spec.ISCSI = iscsiSource
        }
    default:
        return
    }

    pv, err = p.kubeClient.Core().PersistentVolumes().Create(pv)
    return
}

func (p *KubernetesPlugin) deleteVolumeAndPV(volume *v1.PersistentVolume) error {
    found, err := p.orchestrator.DeleteVolume(volume.GetName())

    err = p.kubeClient.Core().PersistentVolumes().Delete(volume.GetName(),
        &metav1.DeleteOptions{})

    return err
}

func getClaimProvisioner(claim *v1.PersistentVolumeClaim) string {
    if provisioner, found := claim.Annotations[AnnStorageProvisioner]; found {
        return provisioner
    }
    return ""
}

func (p *KubernetesPlugin) addVolume(obj interface{}) {
    volume, ok := obj.(*v1.PersistentVolume)
    p.processVolume(volume, "add")
}

func (p *KubernetesPlugin) updateVolume(oldObj, newObj interface{}) {
    volume, ok := newObj.(*v1.PersistentVolume)
    p.processVolume(volume, "update")
}

func (p *KubernetesPlugin) deleteVolume(obj interface{}) {
    volume, ok := obj.(*v1.PersistentVolume)
    p.processVolume(volume, "delete")
}

func (p *KubernetesPlugin) processVolume(
    volume *v1.PersistentVolume,
    eventType string,
) {
    switch eventType {
    case "delete":
        p.processDeletedVolume(volume)
        return
    case "add", "update":
        p.processUpdatedVolume(volume)
    default:
        return
    }
}

func (p *KubernetesPlugin) processDeletedVolume(volume *v1.PersistentVolume) {
    // This method can get called under two scenarios:
    // (1) Deletion of a PVC has resulted in deletion of a PV and the
    //     corresponding volume.
    // (2) An admin has deleted the PV before deleting PVC. processLostClaim
    //     should handle this scenario.
    // Therefore, no action needs to be taken here.
}

func (p *KubernetesPlugin) processUpdatedVolume(volume *v1.PersistentVolume) {
    switch volume.Status.Phase {
    case v1.VolumePending:
        return
    case v1.VolumeAvailable:
        return
    case v1.VolumeBound:
        return
    case v1.VolumeReleased, v1.VolumeFailed:
        if volume.Spec.PersistentVolumeReclaimPolicy != v1.PersistentVolumeReclaimDelete {
            return
        }
        found, err := p.orchestrator.DeleteVolume(volume.Name)

        err = p.kubeClient.Core().PersistentVolumes().Delete(volume.Name,
            &metav1.DeleteOptions{})
    default:
    }
}

func (p *KubernetesPlugin) addClass(obj interface{}) {
    class, ok := obj.(*k8s_storage_v1beta.StorageClass)
    if ok {
        p.processClass(convertStorageClassV1BetaToV1(class), "add")
        return
    }
    classV1, ok := obj.(*k8s_storage_v1.StorageClass)
    p.processClass(classV1, "add")
}

func (p *KubernetesPlugin) updateClass(oldObj, newObj interface{}) {
    class, ok := newObj.(*k8s_storage_v1beta.StorageClass)
    if ok {
        p.processClass(convertStorageClassV1BetaToV1(class), "update")
        return
    }
    classV1, ok := newObj.(*k8s_storage_v1.StorageClass)
    p.processClass(classV1, "update")
}

func (p *KubernetesPlugin) deleteClass(obj interface{}) {
    class, ok := obj.(*k8s_storage_v1beta.StorageClass)
    if ok {
        p.processClass(convertStorageClassV1BetaToV1(class), "delete")
        return
    }
    classV1, ok := obj.(*k8s_storage_v1.StorageClass)
    p.processClass(classV1, "delete")
}

func (p *KubernetesPlugin) processClass(
    class *k8s_storage_v1.StorageClass,
    eventType string,
) {
    if class.Provisioner != AnnOrchestrator {
        return
    }
    switch eventType {
    case "add":
        p.processAddedClass(class)
    case "delete":
        p.processDeletedClass(class)
    case "update":
        // Make sure Trident has a record of this storage class.
        storageClass := p.orchestrator.GetStorageClass(class.Name)
        p.processUpdatedClass(class)
    default:
        return
    }
}

func (p *KubernetesPlugin) processAddedClass(class *k8s_storage_v1.StorageClass) {
    scConfig := new(storage_class.Config)
    scConfig.Name = class.Name
    scConfig.Attributes = make(map[string]storage_attribute.Request)
    k8sStorageClassParams := make(map[string]string)

    // Populate storage class config attributes and backend storage pools
    for k, v := range class.Parameters {
        switch k {
        case K8sFsType:
            // Process Kubernetes-defined storage class parameters
            k8sStorageClassParams[k] = v

        case storage_attribute.RequiredStorage, storage_attribute.AdditionalStoragePools:
            // format:  additionalStoragePools: "backend1:pool1,pool2;backend2:pool1"
            additionalPools, err := storage_attribute.CreateBackendStoragePoolsMapFromEncodedString(v)
            scConfig.AdditionalPools = additionalPools

        case storage_attribute.StoragePools:
            // format:  storagePools: "backend1:pool1,pool2;backend2:pool1"
            pools, err := storage_attribute.CreateBackendStoragePoolsMapFromEncodedString(v)
            scConfig.Pools = pools

        default:
            // format:  attribute: "value"
            req, err := storage_attribute.CreateAttributeRequestFromAttributeValue(k, v)
            scConfig.Attributes[k] = req
        }
    }

    // Update Kubernetes-defined storage class parameters maintained by the
    // frontend. Note that these parameters are only processed by the frontend
    // and not by Trident core.
    p.mutex.Lock()
    storageClassSummary := &StorageClassSummary{
        Parameters:                    k8sStorageClassParams,
        MountOptions:                  class.MountOptions,
        PersistentVolumeReclaimPolicy: class.ReclaimPolicy,
    }
    p.storageClassCache[class.Name] = storageClassSummary
    p.mutex.Unlock()

    // Add the storage class
    sc, err := p.orchestrator.AddStorageClass(scConfig)
    if sc != nil {
        // Check if it's a default storage class
        if getAnnotation(class.Annotations, AnnDefaultStorageClass) == "true" {
            p.mutex.Lock()
            p.defaultStorageClasses[class.Name] = true
            p.mutex.Unlock()
        }
    }
    return
}

func (p *KubernetesPlugin) processDeletedClass(class *k8s_storage_v1.StorageClass) {
    // Check if we're deleting the default storage class.
    if getAnnotation(class.Annotations, AnnDefaultStorageClass) == "true" {
        p.mutex.Lock()
        if p.defaultStorageClasses[class.Name] {
            delete(p.defaultStorageClasses, class.Name)
        }
        p.mutex.Unlock()
    }

    // Delete the storage class.
    deleted, err := p.orchestrator.DeleteStorageClass(class.Name)
    return
}

func (p *KubernetesPlugin) processUpdatedClass(class *k8s_storage_v1.StorageClass) {
    if p.defaultStorageClasses[class.Name] {
        // It's an update to a default storage class.
        // Check to see if it's still a default storage class.
        if getAnnotation(class.Annotations, AnnDefaultStorageClass) != "true" {
            delete(p.defaultStorageClasses, class.Name)
            return
        }
        return
    } else {
        // It's an update to a non-default storage class.
        if getAnnotation(class.Annotations, AnnDefaultStorageClass) == "true" {
            // The update defines a new default storage class.
            p.defaultStorageClasses[class.Name] = true
            return
        }
        return
    }
}

// GetPersistentVolumeClaimClass returns StorageClassName. If no storage class wasß
// requested, it returns "".
func GetPersistentVolumeClaimClass(claim *v1.PersistentVolumeClaim) string {
    // Use beta annotation first
    if class, found := claim.Annotations[AnnClass]; found {
        return class
    }

    if claim.Spec.StorageClassName != nil {
        return *claim.Spec.StorageClassName
    }

    return ""
}
```

## kubernetes/volumes.go

```go
// getVolumeConfig generates a NetApp DVP volume config from the specs pulled
// from the PVC.
func getVolumeConfig(
    accessModes []v1.PersistentVolumeAccessMode,
    name string,
    size resource.Quantity,
    annotations map[string]string,
) *storage.VolumeConfig {
    var accessMode config.AccessMode

    if len(accessModes) > 1 {
        accessMode = config.ReadWriteMany
    } else if len(accessModes) == 0 {
        accessMode = config.ModeAny //or config.ReadWriteMany?
    } else {
        accessMode = config.AccessMode(accessModes[0])
    }

    if getAnnotation(annotations, AnnFileSystem) == "" {
        annotations[AnnFileSystem] = "ext4"
    }

    return &storage.VolumeConfig{
        Name:              name,
        Size:              fmt.Sprintf("%d", size.Value()),
        Protocol:          config.Protocol(getAnnotation(annotations, AnnProtocol)),
        SnapshotPolicy:    getAnnotation(annotations, AnnSnapshotPolicy),
        ExportPolicy:      getAnnotation(annotations, AnnExportPolicy),
        SnapshotDir:       getAnnotation(annotations, AnnSnapshotDir),
        UnixPermissions:   getAnnotation(annotations, AnnUnixPermissions),
        StorageClass:      getAnnotation(annotations, AnnClass),
        BlockSize:         getAnnotation(annotations, AnnBlockSize),
        FileSystem:        getAnnotation(annotations, AnnFileSystem),
        CloneSourceVolume: getAnnotation(annotations, AnnCloneFromPVC),
        SplitOnClone:      getAnnotation(annotations, AnnSplitOnClone),
        AccessMode:        accessMode,
    }
}

func CreateNFSVolumeSource(vol *storage.VolumeExternal) *v1.NFSVolumeSource {
    volConfig := vol.Config
    return &v1.NFSVolumeSource{
        Server: volConfig.AccessInfo.NfsServerIP,
        Path:   volConfig.AccessInfo.NfsPath,
    }
}
```
