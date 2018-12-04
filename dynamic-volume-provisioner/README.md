<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [关于 nfs-client-provisioner 的补充说明](#%E5%85%B3%E4%BA%8E-nfs-client-provisioner-%E7%9A%84%E8%A1%A5%E5%85%85%E8%AF%B4%E6%98%8E)
- [nfs-client-provisioner 源码分析](#nfs-client-provisioner-%E6%BA%90%E7%A0%81%E5%88%86%E6%9E%90)
  - [main 函数分析](#main-%E5%87%BD%E6%95%B0%E5%88%86%E6%9E%90)
  - [Provision 函数分析](#provision-%E5%87%BD%E6%95%B0%E5%88%86%E6%9E%90)
  - [Delete 函数分析](#delete-%E5%87%BD%E6%95%B0%E5%88%86%E6%9E%90)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# 关于 nfs-client-provisioner 的补充说明

首先我们会部署 nfs-client-provisioner Deployment：

```
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: nfs-client-provisioner
spec:
  replicas: 1
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: nfs-client-provisioner
    spec:
      serviceAccountName: nfs-client-provisioner
      containers:
        - name: nfs-client-provisioner
          image: quay.io/external_storage/nfs-client-provisioner:latest
          volumeMounts:
            - name: nfs-client-root
              mountPath: /persistentvolumes
          env:
            - name: PROVISIONER_NAME
              value: fuseim.pri/ifs
            - name: NFS_SERVER
              value: 10.10.10.60
            - name: NFS_PATH
              value: /ifs/kubernetes
      volumes:
        - name: nfs-client-root
          nfs:
            server: 10.10.10.60
            path: /ifs/kubernetes
```

其中，env 是 nfs-client-provisioner 程序需要的环境配置。而该 Deployment 中的 volumes 指定的 nfs 提供的 volume，这里用的 k8s 普通 volume（非 persistentVolumeClaim volume，参考：../volume/nfs-plugin.md）。

从 Deployment 中我们可以看出，我们会将 nfs server 的 `/ifs/kubernetes` 目录挂载到 nfs-client-provisioner 容器的 `/persistentvolumes` 目录。

当 nfs-client-provisioner 需要创建 dynamic pv，并将该 pv 对应的 volume mount 到容器路径的时候，操作步骤如下：

1. nfs-client-provisioner 先在 `/persistentvolumes` 创建一个 pvName 目录，即 `/persistentvolumes/pvName`；实际上就是在 nfs server `/ifs/kubernetes` 目录下创建了一个 pvName 目录，即 `/ifs/kubernetes/pvName`
2. 创建并返回一个路径为 `/ifs/kubernetes/pvName` 的 pv

然后，kubelet 的 nfs plugin 会将 nfs server 提供的 dynamic pv 的 `/ifs/kubernetes/pvName` 目录挂载到容器指定的挂载点。

# nfs-client-provisioner 源码分析

代码路径：`kubernetes-incubator/external-storage/nfs-client/cmd/nfs-client-provisioner/provisioner.go`

## main 函数分析

```
const (
    provisionerNameKey = "PROVISIONER_NAME"
)

func main() {
    server := os.Getenv("NFS_SERVER")
    path := os.Getenv("NFS_PATH")
    provisionerName := os.Getenv(provisionerNameKey)

    ...

    clientNFSProvisioner := &nfsProvisioner{
        client: clientset,
        server: server,
        # nfs-client-provisioner 会在 NFS_PATH 路径下
        # 创建 pvName 子目录，然后将子目录挂载到容器指定挂载目录
        path:   path,
    }
    // Start the provision controller which will dynamically provision efs NFS
    // PVs
    pc := controller.NewProvisionController(clientset, provisionerName, clientNFSProvisioner, serverVersion.GitVersion)
    pc.Run(wait.NeverStop)
}
```

## Provision 函数分析

```
const (
    mountPath = "/persistentvolumes"
)

/* nfs server NFS_PATH 目录挂载到 nfs-client-provisioner pod
 * 创建 dynamic pv 的时候，现在 nfs server NFS_PATH 目录下创建一个 pvName 的子目录
 * 然后创建并返回一个基于 nfs NFS_PATH/pvName 路径的 pv
 */
func (p *nfsProvisioner) Provision(options controller.VolumeOptions) (*v1.PersistentVolume, error) {
    pvcNamespace := options.PVC.Namespace
    pvcName := options.PVC.Name

    pvName := strings.Join([]string{pvcNamespace, pvcName, options.PVName}, "-")

    fullPath := filepath.Join(mountPath, pvName)
    /* 创建 mountPath/pvName 目录，即 NFS_PATH/pvName 目录 */
    if err := os.MkdirAll(fullPath, 0777); err != nil {
        return nil, errors.New("unable to create directory to provision new pv: " + err.Error())
    }
    os.Chmod(fullPath, 0777)

    /* path 为 NFS_PATH/pvName 目录 */
    path := filepath.Join(p.path, pvName)

    /* 构建基于 NFS_PATH/pvName 目录的 pv */
    pv := &v1.PersistentVolume{
        ObjectMeta: metav1.ObjectMeta{
            Name: options.PVName,
        },
        Spec: v1.PersistentVolumeSpec{
            PersistentVolumeReclaimPolicy: options.PersistentVolumeReclaimPolicy,
            AccessModes:                   options.PVC.Spec.AccessModes,
            MountOptions:                  options.MountOptions,
            Capacity: v1.ResourceList{
                v1.ResourceName(v1.ResourceStorage): options.PVC.Spec.Resources.Requests[v1.ResourceName(v1.ResourceStorage)],
            },
            PersistentVolumeSource: v1.PersistentVolumeSource{
                NFS: &v1.NFSVolumeSource{
                    Server:   p.server,
                    Path:     path,
                    ReadOnly: false,
                },
            },
        },
    }

    /* 返回一个基于 nfs NFS_PATH/pvName 路径的 pv */
    return pv, nil
}
```

## Delete 函数分析

```
/* Delete 函数要么将 pvName 目录从 nfs server 中删除 
 * 要么在 nfs server 中将 mountPath/pvName move 成 mountPath/archived-pvName
 */
func (p *nfsProvisioner) Delete(volume *v1.PersistentVolume) error {
    path := volume.Spec.PersistentVolumeSource.NFS.Path
    pvName := filepath.Base(path)
    oldPath := filepath.Join(mountPath, pvName)
    if _, err := os.Stat(oldPath); os.IsNotExist(err) {
        glog.Warningf("path %s does not exist, deletion skipped", oldPath)
        return nil
    }
    // Get the storage class for this volume.
    storageClass, err := p.getClassForVolume(volume)
    if err != nil {
        return err
    }
    // Determine if the "archiveOnDelete" parameter exists.
    // If it exists and has a falsey value, delete the directory.
    // Otherwise, archive it.
    archiveOnDelete, exists := storageClass.Parameters["archiveOnDelete"]
    if exists {
        archiveBool, err := strconv.ParseBool(archiveOnDelete)
        if err != nil {
            return err
        }
        if !archiveBool {
            return os.RemoveAll(oldPath)
        }
    }

    archivePath := filepath.Join(mountPath, "archived-"+pvName)
    glog.V(4).Infof("archiving path %s to %s", oldPath, archivePath)
    return os.Rename(oldPath, archivePath)

}
```


