# netprofile create

```
NAME:
   netctl netprofile create - Create a network profile

USAGE:
   netctl netprofile create [command options] [netprofile]

OPTIONS:
   --tenant, -t "default"   Name of the tenant
   --bandwidth, -b      Bandwidth (e.g., 10 kbps, 100 mbps, 1gbps)
   --dscp, -d "0"       DSCP
   --burst, -s "0"      burst size(Must be in kilobytes)
```

创建 endpoint group 的时候，可以指定为该 group 使用那个 netprofile 来做网络带宽限制.

```
NAME:
   netctl group create - Create an endpoint group

USAGE:
   netctl group create [command options] [network] [group]

OPTIONS:
   --tenant, -t "default"                               Name of the tenant
   --policy, -p [--policy option --policy option]                   Policy
   --networkprofile, -n                                 network profile
   --external-contract, -e [--external-contract option --external-contract option]  External contract
   --ip-pool, -r                                    IP Address range, example 10.36.0.1-10.36.0.10
   --epg-tag, --tag                                     Configured Group Tag
```

![netprofile create](netprofile-create.png)

## netmaster 流程

### httpCreateNetprofile

**contivmodel/contivModel.go**

// CREATE REST call
func httpCreateNetprofile(w http.ResponseWriter, r *http.Request, vars map[string]string) (interface{}, error) {

    var obj Netprofile
    key := vars["key"]

    // Get object from the request
    err := json.NewDecoder(r.Body).Decode(&obj)

    // Create the object
    err = CreateNetprofile(&obj)

    // Return the obj
    return obj, nil
}

// Create a netprofile object
func CreateNetprofile(obj *Netprofile) error {

    saveObj := obj

    collections.netprofileMutex.Lock()
    key := collections.netprofiles[obj.Key]
    collections.netprofileMutex.Unlock()

    // Check if object already exists
    if key != nil {
        // Perform Update callback
        err = objCallbackHandler.NetprofileCb.NetprofileUpdate(collections.netprofiles[obj.Key], obj)
        if err != nil {
            log.Errorf("NetprofileUpdate retruned error for: %+v. Err: %v", obj, err)
            return err
        }

        // save the original object after update
        collections.netprofileMutex.Lock()
        saveObj = collections.netprofiles[obj.Key]
        collections.netprofileMutex.Unlock()
    } else {
        // save it in cache
        collections.netprofileMutex.Lock()
        collections.netprofiles[obj.Key] = obj
        collections.netprofileMutex.Unlock()

        // Perform Create callback
        err = objCallbackHandler.NetprofileCb.NetprofileCreate(obj)
        if err != nil {
            log.Errorf("NetprofileCreate retruned error for: %+v. Err: %v", obj, err)
            collections.netprofileMutex.Lock()
            delete(collections.netprofiles, obj.Key)
            collections.netprofileMutex.Unlock()
            return err
        }
    }

    // Write it to modeldb
    collections.netprofileMutex.Lock()
    err = saveObj.Write()
    collections.netprofileMutex.Unlock()
    if err != nil {
        log.Errorf("Error saving netprofile %s to db. Err: %v", saveObj.Key, err)
        return err
    }

    return nil
}

**netmaster/objApi/apiController.go**

// NetprofileCreate creates the network rule
func (ac *APIController) NetprofileCreate(netProfile *contivModel.Netprofile) error {

    tenant := contivModel.FindTenant(netProfile.TenantName)

    // Setup links & Linksets.
    modeldb.AddLink(&netProfile.Links.Tenant, tenant)
    modeldb.AddLinkSet(&tenant.LinkSets.NetProfiles, netProfile)

    // Save the tenant in etcd - This writes to etcd.
    err := tenant.Write()

    return nil
}

# netprofile delete

```
NAME:
   netctl netprofile rm - Delete a network profile

USAGE:
   netctl netprofile rm [command options] [network] [group]

OPTIONS:
   --tenant, -t "default"   Name of the tenant
```

![netprofile delete](netprofile-delete.png)

## netmaster 流程

### httpDeleteNetprofile

**contivmodel/contivModel.go**

// DELETE rest call
func httpDeleteNetprofile(w http.ResponseWriter, r *http.Request, vars map[string]string) (interface{}, error) {
    log.Debugf("Received httpDeleteNetprofile: %+v", vars)

    key := vars["key"]

    // Delete the object
    err := DeleteNetprofile(key)

    // Return the obj
    return key, nil
}

// Delete a netprofile object
func DeleteNetprofile(key string) error {
    collections.netprofileMutex.Lock()
    obj := collections.netprofiles[key]
    collections.netprofileMutex.Unlock()

    // Check if we handle this object
    if objCallbackHandler.NetprofileCb == nil {
        log.Errorf("No callback registered for netprofile object")
        return errors.New("Invalid object type")
    }

    // Perform callback
    err := objCallbackHandler.NetprofileCb.NetprofileDelete(obj)

    // delete it from modeldb
    collections.netprofileMutex.Lock()
    err = obj.Delete()
    collections.netprofileMutex.Unlock()
    if err != nil {
        log.Errorf("Error deleting netprofile %s. Err: %v", obj.Key, err)
    }

    // delete it from cache
    collections.netprofileMutex.Lock()
    delete(collections.netprofiles, key)
    collections.netprofileMutex.Unlock()

    return nil
}

**netmaster/objApi/apiController.go**

// NetprofileDelete deletes netprofile
func (ac *APIController) NetprofileDelete(netProfile *contivModel.Netprofile) error {
    log.Infof("Deleting Netprofile:%s", netProfile.ProfileName)

    // Find Tenant
    tenant := contivModel.FindTenant(netProfile.TenantName)
    if tenant == nil {
        return core.Errorf("Tenant %s not found", netProfile.TenantName)
    }
    // Check if any endpoint group is using the network policy
    if len(netProfile.LinkSets.EndpointGroups) != 0 {
        return core.Errorf("NetProfile is being used")
    }

    modeldb.RemoveLinkSet(&tenant.LinkSets.NetProfiles, netProfile)
    return nil
}
