<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [PV/PVC](#pvpvc)
- [PV and PVC share](#pv-and-pvc-share)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# PV/PVC

Three approaches to use cloud disk:

- If you know the clear cloud disk id, just use it
- PV/PVC mechanisam
- Auto-provision PVC

# PV and PVC share

You can share pv and pvc within the same namespace for shared volumes (nfs, glusterfs, ...), you can also access your shared volume from multiple namespace, but it will require dedicated pv and pvs, as a pv is bound to a single namespace and pvc is namespace scoped.

The pv is global that it can be seen by any namespace, but once it is bound to a namespace, it can then only be accessed by containers from the same namespace.

The pvc is namespace scoped. If you have multiple namespaces you would need to have a new pv and pvc for each namespace to connect to the shared nfs volume, and you cann't reuse the pv in the first namespace.

Example 1:
Two distinct pods running the same namespace, both access the same pv and nfs exported share with the same pvc.

Example 2:
In namespace1, i have two pods share the same pv and the shared nfs volume with the same pvc. In namespace2, i would need another pv and pvc to share the nfs exported volume.

Example 3:
If bypassing pv and pvc, i can connect to the shared nfs volume directly from any namespace container by using the nfs plugin directly:

    ```
    volume:
    - name: nfs-volume
      nfs:
        path: /xxxx/yyyy
        server: 192.168.1.10
    ```

Container's access mode seprated from pv/pvc's access mode. The later is for node, and the former is for container. We can mount a nfs volume with RW mode, but just let containter access the volume with RO mode when mapping the volume to container.
