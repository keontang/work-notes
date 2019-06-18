<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Network Policies](#network-policies)
  - [Network Isolation Policies](#network-isolation-policies)
    - [Creating a Policy Using the CLI](#creating-a-policy-using-the-cli)
    - [Associating a Network Isolation Policy to a Group](#associating-a-network-isolation-policy-to-a-group)
    - [Associating Multiple Policies with a Group](#associating-multiple-policies-with-a-group)
    - [Associating a Policy with Multiple Groups](#associating-a-policy-with-multiple-groups)
  - [Network Bandwidth Limiting](#network-bandwidth-limiting)
    - [Creating a Bandwidth Policy using the CLI](#creating-a-bandwidth-policy-using-the-cli)
    - [Using Traffic Prioritization for Network-Wide Application Behavior](#using-traffic-prioritization-for-network-wide-application-behavior)
- [policy restful api 分析](#policy-restful-api-%E5%88%86%E6%9E%90)
  - [policy create](#policy-create)
  - [policy delete](#policy-delete)
- [netprofile restful api 分析](#netprofile-restful-api-%E5%88%86%E6%9E%90)
  - [netprofile create](#netprofile-create)
  - [netprofile delete](#netprofile-delete)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Network Policies

Network policies describe rules for network resource usage, isolation rules, prioritization, and other network behavior on a group of containers.

There are two types of network policies you can create with Contiv:

- Bandwidth - limiting the overall resource use of a group
- Isolation - limiting the access of a group

This section covers how to create, update, and delete these policies.

## Network Isolation Policies

Network isolation policies enable white-list or black-list access control rules to or from an application. Network isolation policies are particularly useful in securing an application tier. A group where an inbound policy is applied can be a service tier or another logical collection of containers that must be part of a policy domain.

### Creating a Policy Using the CLI

You can create a policy using the create operation on a policy object. During creation, the policy must be supplied with a unique name in the tenant namespace.

The following command creates a policy named web-policy:

`$ netctl policy create web-policy`

A network isolation policy can have access control list -style whitelist or blacklist rules. A policy rule can specify the following information:

- match criteria: Specified using protocol and optionally a port. If match criteria are not specified then the rule matches all traffic If only protocol is specified but port is omitted, then the traffic matches all ports.
  - protocol: Layer3 (IP, ICMP) or Layer4 (TCP, UDP).
  - port: a TCP or UDP port number to or from which to permit or deny traffic.
  - ip-address: Can specify a masked IP address pool, which can be used to specify a rules to or from the address pool. It is often useful to specify these rules to and from non-container workloads.
- direction: Can be inbound or outbound, from the container application's point of view. An inbound rule is applicable to the traffic coming in to the containers; an outbound rule is applicable to the traffic going out from the container.
- action: A permit or deny action on the traffic that matches the rule. A white-list set of rules is typically a set of permit actions followed by a rule to deny the rest.
- priority: Determines the execution order of the rules, producing a predictable behavior for a set of arbitrary rules.
- from-group: Used to permit or deny traffic to or from specific containers, identified as a group.

For example, A policy to allow inbound access to tcp/80 and tcp/443 and deny all other traffic looks like this:

```
netctl policy rule-add web-policy 1 -direction=in -protocol=tcp -action=deny
netctl policy rule-add web-policy 2 -direction=in -protocol=tcp -port=80 -action=allow -priority=10
netctl policy rule-add web-policy 3 -direction=in -protocol=tcp -port=443 -action=allow -priority=10
```

### Associating a Network Isolation Policy to a Group

After defining a security policy, you associate it with a group on an existing network contiv-net as follows:

```
netctl group create contiv-net web-group -policy=web-policy
```

For Kubernetes: Specify the group association as a label io.contiv.net-group. For example, a service (or pod) specification might look like:

```
apiVersion: v1
kind: ReplicationController
metadata:
  name: prod-web
spec:
  replicas: 2
  selector:
    app: prod-web
  template:
    metadata:
      labels:
        app: prod-web
        io.contiv.net-group: web-group
    spec:
      containers:
      - name: prod-web
        image: alpine
        command:
          - /bin/sh
```

Kubernetes offers richer options for selection criteria because of the selector concept, which allows arbitrary selection of collections of labels to form a dynamic group. For example, a collection of {'prod', 'web'} ond {'stage', 'db', 'low-latency'} can both be implicit groups.

### Associating Multiple Policies with a Group

The policy system is dynamic in the following two ways:

- Policy rules can be altered after the policy is defined.
- Policy associations can be added to or removed from a group of containers at any time.

### Associating a Policy with Multiple Groups

A policy can be applied to multiple groups. In other words, a policy is reusable across groups. 

## Network Bandwidth Limiting

Network bandwidth policies specify the bandwidth limits on all containers that belong to a group. These policies "throttle" the bandwidth of every container belonging to a specific group.

### Creating a Bandwidth Policy using the CLI

Policies like network isolation apply between two groups, whereas other policies, including network bandwidth allocation, affect a group or containers within a group.

A netwrok-profile describes various attributes that apply to a group, for example network bandwidth limits. A network-profile can be created as follows:

```
$ netctl netprofile create -b 1Mbps -dscp 3 dev-net-profile
Name            Tenant      Bandwidth   DSCP
----            ------      ---------   ----
dev-net-profile     default     1Mbps       3
```

This network profile limits associated containers to a network bandwidth of 1Mbps and sets their DSCP (Differentiated Services Code Point, or type of service) bits in the IP header.

After creation, a profile can be associated with a group:

```
$ netctl group create contiv-net dev-web-group -policy=allow-diags -networkprofile=dev-net-profile
$ netctl group ls
Tenant   Group            Network     Policies          Network Profile
------   -----            -------     --------          ---------------
default  stage-web-group  contiv-net  web-policy,allow-diags    default
default  dev-web-group    contiv-net  allow-diags       dev-net-profile
```

At this point the bandwidth policy is in force on the dev-web-group.

### Using Traffic Prioritization for Network-Wide Application Behavior

Note: This section is for more advanced network administrators and engineers.

If a physical network is configured with the classes of traffic identified with DSCP, then a DSCP marking can achieve an end to end application behavior. For example, most of the physical network switching vendors, like Cisco, provide a way to allow use of network bandwidth and traffic scheduling based on DSCP. Configuring physical network devices is out of scope for this document; however, it is worth noting that these features provide:

- Bandwidth allocation: Specify how much packet buffering is allocated to a given class of service (CoS).
- Bandwidth rate limiting: Rate-limit the traffic belonging to a class and specify the rules of traffic precedence during bursts or contention. This can provide network predictability to classes of traffic.
- Traffic scheduling: Usually the default scheduling policy on a switch is to round-robin the traffic towards different destinations. In cases of contention, however, a more sophisticated scheduling policy can be defined based on DSCP.

The integration of DSCP prioritization with an application can contribute to predictable behavior for network and/or storage traffic.

# policy restful api 分析

## policy create

```
NAME:
   netctl policy create - Create a new policy

USAGE:
   netctl policy create [command options] [policy]

OPTIONS:
   --tenant, -t "default"   Name of the tenant
```

**contivModel/contivModelClient.go**

// Policy object
type Policy struct {
    // every object has a key
    Key string `json:"key,omitempty"`

    PolicyName string `json:"policyName,omitempty"` // Policy Name
    TenantName string `json:"tenantName,omitempty"` // Tenant Name

    // add link-sets and links
    LinkSets PolicyLinkSets `json:"link-sets,omitempty"`
    Links    PolicyLinks    `json:"links,omitempty"`
}

**contivModel/contivModel.go**

// CREATE REST call
func httpCreatePolicy(w http.ResponseWriter, r *http.Request, vars map[string]string) (interface{}, error) {
    log.Debugf("Received httpGetPolicy: %+v", vars)

    var obj Policy
    key := vars["key"]

    // Get object from the request
    err := json.NewDecoder(r.Body).Decode(&obj)
    if err != nil {
        log.Errorf("Error decoding policy create request. Err %v", err)
        return nil, err
    }

    // set the key
    obj.Key = key

    // Create the object
    err = CreatePolicy(&obj)
    if err != nil {
        log.Errorf("CreatePolicy error for: %+v. Err: %v", obj, err)
        return nil, err
    }

    // Return the obj
    return obj, nil
}

// Create a policy object
func CreatePolicy(obj *Policy) error {
    // Validate parameters
    err := ValidatePolicy(obj)
    if err != nil {
        log.Errorf("ValidatePolicy retruned error for: %+v. Err: %v", obj, err)
        return err
    }

    // objCallbackHandler.PolicyCb 为 apiController
    // Check if we handle this object
    if objCallbackHandler.PolicyCb == nil {
        log.Errorf("No callback registered for policy object")
        return errors.New("Invalid object type")
    }

    saveObj := obj

    collections.policyMutex.Lock()
    key := collections.policys[obj.Key]
    collections.policyMutex.Unlock()

    // Check if object already exists
    if key != nil {
        // Perform Update callback
        err = objCallbackHandler.PolicyCb.PolicyUpdate(collections.policys[obj.Key], obj)
        if err != nil {
            log.Errorf("PolicyUpdate retruned error for: %+v. Err: %v", obj, err)
            return err
        }

        // save the original object after update
        collections.policyMutex.Lock()
        saveObj = collections.policys[obj.Key]
        collections.policyMutex.Unlock()
    } else {
        // save it in cache
        collections.policyMutex.Lock()
        collections.policys[obj.Key] = obj
        collections.policyMutex.Unlock()

        // Perform Create callback
        err = objCallbackHandler.PolicyCb.PolicyCreate(obj)
        if err != nil {
            log.Errorf("PolicyCreate retruned error for: %+v. Err: %v", obj, err)
            collections.policyMutex.Lock()
            delete(collections.policys, obj.Key)
            collections.policyMutex.Unlock()
            return err
        }
    }

    // Write it to modeldb
    collections.policyMutex.Lock()
    err = saveObj.Write()
    collections.policyMutex.Unlock()
    if err != nil {
        log.Errorf("Error saving policy %s to db. Err: %v", saveObj.Key, err)
        return err
    }

    return nil
}

**netmaster/objApi/apiController.go**

// PolicyCreate creates policy
func (ac *APIController) PolicyCreate(policy *contivModel.Policy) error {
    log.Infof("Received PolicyCreate: %+v", policy)

    // Make sure tenant exists
    if policy.TenantName == "" {
        return core.Errorf("Invalid tenant name")
    }

    tenant := contivModel.FindTenant(policy.TenantName)
    if tenant == nil {
        return core.Errorf("Tenant not found")
    }

    // Setup links
    modeldb.AddLink(&policy.Links.Tenant, tenant)
    modeldb.AddLinkSet(&tenant.LinkSets.Policies, policy)

    // Save the tenant too since we added the links
    err := tenant.Write()
    if err != nil {
        log.Errorf("Error updating tenant state(%+v). Err: %v", tenant, err)
        return err
    }

    return nil
}

## policy delete

**contivModel/contivModel.go**

// DELETE rest call
func httpDeletePolicy(w http.ResponseWriter, r *http.Request, vars map[string]string) (interface{}, error) {
    log.Debugf("Received httpDeletePolicy: %+v", vars)

    key := vars["key"]

    // Delete the object
    err := DeletePolicy(key)
    if err != nil {
        log.Errorf("DeletePolicy error for: %s. Err: %v", key, err)
        return nil, err
    }

    // Return the obj
    return key, nil
}

// Delete a policy object
func DeletePolicy(key string) error {
    collections.policyMutex.Lock()
    obj := collections.policys[key]
    collections.policyMutex.Unlock()
    if obj == nil {
        log.Errorf("policy %s not found", key)
        return errors.New("policy not found")
    }

    // Check if we handle this object
    if objCallbackHandler.PolicyCb == nil {
        log.Errorf("No callback registered for policy object")
        return errors.New("Invalid object type")
    }

    // Perform callback
    err := objCallbackHandler.PolicyCb.PolicyDelete(obj)
    if err != nil {
        log.Errorf("PolicyDelete retruned error for: %+v. Err: %v", obj, err)
        return err
    }

    // delete it from modeldb
    collections.policyMutex.Lock()
    err = obj.Delete()
    collections.policyMutex.Unlock()
    if err != nil {
        log.Errorf("Error deleting policy %s. Err: %v", obj.Key, err)
    }

    // delete it from cache
    collections.policyMutex.Lock()
    delete(collections.policys, key)
    collections.policyMutex.Unlock()

    return nil
}

**netmaster/objApi/apiController.go**

// PolicyDelete deletes policy
func (ac *APIController) PolicyDelete(policy *contivModel.Policy) error {
    log.Infof("Received PolicyDelete: %+v", policy)

    // Find Tenant
    tenant := contivModel.FindTenant(policy.TenantName)
    if tenant == nil {
        return core.Errorf("Tenant %s not found", policy.TenantName)
    }

    // Check if any endpoint group is using the Policy
    if len(policy.LinkSets.EndpointGroups) != 0 {
        return core.Errorf("Policy is being used")
    }

    // Delete all associated Rules
    for key := range policy.LinkSets.Rules {
        // delete the rule
        err := contivModel.DeleteRule(key)
        if err != nil {
            log.Errorf("Error deleting the rule: %s. Err: %v", key, err)
        }
    }

    //Remove Links
    modeldb.RemoveLinkSet(&tenant.LinkSets.Policies, policy)

    // Save the tenant too since we added the links
    err := tenant.Write()
    if err != nil {
        log.Errorf("Error updating tenant state(%+v). Err: %v", tenant, err)
        return err
    }

    return nil
}

# netprofile restful api 分析

## netprofile create

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

**contivModel/contivModel.go**

// CREATE REST call
func httpCreateNetprofile(w http.ResponseWriter, r *http.Request, vars map[string]string) (interface{}, error) {
    log.Debugf("Received httpGetNetprofile: %+v", vars)

    var obj Netprofile
    key := vars["key"]

    // Get object from the request
    err := json.NewDecoder(r.Body).Decode(&obj)
    if err != nil {
        log.Errorf("Error decoding netprofile create request. Err %v", err)
        return nil, err
    }

    // set the key
    obj.Key = key

    // Create the object
    err = CreateNetprofile(&obj)
    if err != nil {
        log.Errorf("CreateNetprofile error for: %+v. Err: %v", obj, err)
        return nil, err
    }

    // Return the obj
    return obj, nil
}

// Create a netprofile object
func CreateNetprofile(obj *Netprofile) error {
    // Validate parameters
    err := ValidateNetprofile(obj)
    if err != nil {
        log.Errorf("ValidateNetprofile retruned error for: %+v. Err: %v", obj, err)
        return err
    }

    // Check if we handle this object
    if objCallbackHandler.NetprofileCb == nil {
        log.Errorf("No callback registered for netprofile object")
        return errors.New("Invalid object type")
    }

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
    log.Infof("Received NetprofileCreate: %+v", netProfile)

    // Check if the tenant exists
    if netProfile.TenantName == "" {
        return core.Errorf("Invalid tenant name")
    }

    if netProfile.Burst > 0 && netProfile.Burst < 2 {
        return core.Errorf("Invalid Burst size. burst size > 1500 bytes")
    }

    tenant := contivModel.FindTenant(netProfile.TenantName)
    if tenant == nil {
        return core.Errorf("Tenant not found")
    }

    // Setup links & Linksets.
    modeldb.AddLink(&netProfile.Links.Tenant, tenant)
    modeldb.AddLinkSet(&tenant.LinkSets.NetProfiles, netProfile)

    // Save the tenant in etcd - This writes to etcd.
    err := tenant.Write()
    if err != nil {
        log.Errorf("Error updating tenant state(%+v). Err: %v", tenant, err)
        return err
    }

    return nil
}

// NetprofileUpdate updates the netprofile
func (ac *APIController) NetprofileUpdate(profile, params *contivModel.Netprofile) error {
    log.Infof("Received NetprofileUpdate: %+v, params: %+v", profile, params)

    if params.Burst > 0 && params.Burst < 2 {
        return core.Errorf("Invalid Burst size. burst size must be > 1500 bytes")
    }
    profile.Bandwidth = params.Bandwidth
    profile.DSCP = params.DSCP
    profile.Burst = params.Burst

    for key := range profile.LinkSets.EndpointGroups {
        // Find the corresponding epg
        epg := contivModel.FindEndpointGroup(key)
        if epg == nil {
            return core.Errorf("EndpointGroups not found")
        }

        err := master.UpdateEndpointGroup(params.Bandwidth, epg.GroupName, epg.TenantName, params.DSCP, params.Burst)
        if err != nil {
            log.Errorf("Error updating the EndpointGroups: %s. Err: %v", epg.GroupName, err)
        }
    }
    return nil
}

## netprofile delete

**contivModel/contivModel.go**

// DELETE rest call
func httpDeleteNetprofile(w http.ResponseWriter, r *http.Request, vars map[string]string) (interface{}, error) {
    log.Debugf("Received httpDeleteNetprofile: %+v", vars)

    key := vars["key"]

    // Delete the object
    err := DeleteNetprofile(key)
    if err != nil {
        log.Errorf("DeleteNetprofile error for: %s. Err: %v", key, err)
        return nil, err
    }

    // Return the obj
    return key, nil
}

// Delete a netprofile object
func DeleteNetprofile(key string) error {
    collections.netprofileMutex.Lock()
    obj := collections.netprofiles[key]
    collections.netprofileMutex.Unlock()
    if obj == nil {
        log.Errorf("netprofile %s not found", key)
        return errors.New("netprofile not found")
    }

    // Check if we handle this object
    if objCallbackHandler.NetprofileCb == nil {
        log.Errorf("No callback registered for netprofile object")
        return errors.New("Invalid object type")
    }

    // Perform callback
    err := objCallbackHandler.NetprofileCb.NetprofileDelete(obj)
    if err != nil {
        log.Errorf("NetprofileDelete retruned error for: %+v. Err: %v", obj, err)
        return err
    }

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
