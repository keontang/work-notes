<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [endpointgroup create](#endpointgroup-create)
  - [netmaster 流程](#netmaster-%E6%B5%81%E7%A8%8B)
    - [httpCreateEndpointGroup](#httpcreateendpointgroup)
  - [netplugin 流程](#netplugin-%E6%B5%81%E7%A8%8B)
    - [handleEpgEvents](#handleepgevents)
    - [processStateEvent](#processstateevent)
    - [processEpgEvent](#processepgevent)
- [endpointgroup delete](#endpointgroup-delete)
  - [netmaster 流程](#netmaster-%E6%B5%81%E7%A8%8B-1)
  - [netplugin 流程](#netplugin-%E6%B5%81%E7%A8%8B-1)
    - [handleEpgEvents](#handleepgevents-1)
    - [processStateEvent 处理 EndpointGroupState 事件](#processstateevent-%E5%A4%84%E7%90%86-endpointgroupstate-%E4%BA%8B%E4%BB%B6)
    - [processEpgEvent](#processepgevent-1)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# endpointgroup create

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

![endpointgroup create](epg-create.png)

## netmaster 流程

### httpCreateEndpointGroup

**contivmodel/contivModel.go**

// CREATE REST call
func httpCreateEndpointGroup(w http.ResponseWriter, r *http.Request, vars map[string]string) (interface{}, error) {
    log.Debugf("Received httpGetEndpointGroup: %+v", vars)

    var obj EndpointGroup
    key := vars["key"]

    // Get object from the request
    err := json.NewDecoder(r.Body).Decode(&obj)

    // set the key
    obj.Key = key

    // Create the object
    err = CreateEndpointGroup(&obj)

    // Return the obj
    return obj, nil
}

// Create a endpointGroup object
func CreateEndpointGroup(obj *EndpointGroup) error {

    saveObj := obj

    collections.endpointGroupMutex.Lock()
    key := collections.endpointGroups[obj.Key]
    collections.endpointGroupMutex.Unlock()

    // Check if object already exists
    if key != nil {
        // Perform Update callback
        err = objCallbackHandler.EndpointGroupCb.EndpointGroupUpdate(collections.endpointGroups[obj.Key], obj)
        if err != nil {
            log.Errorf("EndpointGroupUpdate retruned error for: %+v. Err: %v", obj, err)
            return err
        }

        // save the original object after update
        collections.endpointGroupMutex.Lock()
        saveObj = collections.endpointGroups[obj.Key]
        collections.endpointGroupMutex.Unlock()
    } else {
        // save it in cache
        collections.endpointGroupMutex.Lock()
        collections.endpointGroups[obj.Key] = obj
        collections.endpointGroupMutex.Unlock()

        // Perform Create callback
        err = objCallbackHandler.EndpointGroupCb.EndpointGroupCreate(obj)
        if err != nil {
            log.Errorf("EndpointGroupCreate retruned error for: %+v. Err: %v", obj, err)
            collections.endpointGroupMutex.Lock()
            delete(collections.endpointGroups, obj.Key)
            collections.endpointGroupMutex.Unlock()
            return err
        }
    }

    // Write it to modeldb
    collections.endpointGroupMutex.Lock()
    err = saveObj.Write()
    collections.endpointGroupMutex.Unlock()
    if err != nil {
        log.Errorf("Error saving endpointGroup %s to db. Err: %v", saveObj.Key, err)
        return err
    }

    return nil
}

**netmaster/objApi/apiController.go**

// FIXME: hack to allocate unique endpoint group ids
var globalEpgID = 1

// EndpointGroupCreate creates Endpoint Group
func (ac *APIController) EndpointGroupCreate(endpointGroup *contivModel.EndpointGroup) error {
    log.Infof("Received EndpointGroupCreate: %+v", endpointGroup)

    // Find the tenant
    tenant := contivModel.FindTenant(endpointGroup.TenantName)
    // Find the network
    nwObjKey := endpointGroup.TenantName + ":" + endpointGroup.NetworkName
    network := contivModel.FindNetwork(nwObjKey)
    // If there is a Network with the same name as this endpointGroup, reject.
    nameClash := contivModel.FindNetwork(endpointGroup.Key)
    // create the endpoint group state
    err := master.CreateEndpointGroup(endpointGroup.TenantName, endpointGroup.NetworkName,
        endpointGroup.GroupName, endpointGroup.IpPool, endpointGroup.CfgdTag)

    // for each policy create an epg policy Instance
    for _, policyName := range endpointGroup.Policies {
        policyKey := GetpolicyKey(endpointGroup.TenantName, policyName)
        // find the policy
        policy := contivModel.FindPolicy(policyKey)
        if policy == nil {
            log.Errorf("Could not find policy %s", policyName)
            endpointGroupCleanup(endpointGroup)
            return core.Errorf("Policy not found")
        }

        // attach policy to epg
        err = master.PolicyAttach(endpointGroup, policy)
        if err != nil {
            log.Errorf("Error attaching policy %s to epg %s", policyName, endpointGroup.Key)
            endpointGroupCleanup(endpointGroup)
            return err
        }

        // establish Links
        modeldb.AddLinkSet(&policy.LinkSets.EndpointGroups, endpointGroup)
        modeldb.AddLinkSet(&endpointGroup.LinkSets.Policies, policy)

        // Write the policy
        err = policy.Write()
        if err != nil {
            endpointGroupCleanup(endpointGroup)
            return err
        }
    }

    // If endpoint group is to be attached to any netprofile, then attach the netprofile and create links and linksets.
    if endpointGroup.NetProfile != "" {
        profileKey := GetNetprofileKey(endpointGroup.TenantName, endpointGroup.NetProfile)
        netprofile := contivModel.FindNetprofile(profileKey)
        if netprofile == nil {
            log.Errorf("Error finding netprofile: %s", profileKey)
            return errors.New("netprofile not found")
        }

        // attach NetProfile to epg
        err = master.UpdateEndpointGroup(netprofile.Bandwidth, endpointGroup.GroupName, endpointGroup.TenantName, netprofile.DSCP, netprofile.Burst)
        if err != nil {
            log.Errorf("Error attaching NetProfile %s to epg %s", endpointGroup.NetProfile, endpointGroup.Key)
            endpointGroupCleanup(endpointGroup)
            return err
        }

        //establish links (epg - netprofile)
        modeldb.AddLink(&endpointGroup.Links.NetProfile, netprofile)
        //establish linksets (Netprofile - epg)
        modeldb.AddLinkSet(&netprofile.LinkSets.EndpointGroups, endpointGroup)

        //Write the attached Netprofile to modeldb
        err = netprofile.Write()
        if err != nil {
            endpointGroupCleanup(endpointGroup)
            return err
        }
    }

    // Setup external contracts this EPG might have.
    err = setupExternalContracts(endpointGroup, endpointGroup.ExtContractsGrps)
    if err != nil {
        log.Errorf("Error setting up external contracts for epg %s", endpointGroup.Key)
        endpointGroupCleanup(endpointGroup)
        return err
    }

    // Setup links
    modeldb.AddLink(&endpointGroup.Links.Network, network)
    modeldb.AddLink(&endpointGroup.Links.Tenant, tenant)
    modeldb.AddLinkSet(&network.LinkSets.EndpointGroups, endpointGroup)
    modeldb.AddLinkSet(&tenant.LinkSets.EndpointGroups, endpointGroup)

    // Save the tenant and network since we added the links
    err = network.Write()
    if err != nil {
        endpointGroupCleanup(endpointGroup)
        return err
    }

    err = tenant.Write()
    if err != nil {
        endpointGroupCleanup(endpointGroup)
        return err
    }

    return nil
}

**netmaster/master/endpointGroup.go**

// CreateEndpointGroup handles creation of endpoint group
func CreateEndpointGroup(tenantName, networkName, groupName, ipPool, cfgdTag string) error {
    var epgID int

    // Get the state driver
    stateDriver, err := utils.GetStateDriver()

    // Read global config
    gstate.GlobalMutex.Lock()
    defer gstate.GlobalMutex.Unlock()
    gCfg := gstate.Cfg{}
    gCfg.StateDriver = stateDriver
    err = gCfg.Read(tenantName)

    // read the network config
    networkID := networkName + "." + tenantName
    nwCfg := &mastercfg.CfgNetworkState{}
    nwCfg.StateDriver = stateDriver
    err = nwCfg.Read(networkID)

    // check epg range is with in network

    // if there is no label given generate one for the epg

    // assign unique endpoint group ids

    // Create epGroup state
    epgCfg := &mastercfg.EndpointGroupState{
        GroupName:       groupName,
        TenantName:      tenantName,
        NetworkName:     networkName,
        IPPool:          ipPool,
        EndpointGroupID: epgID,
        PktTagType:      nwCfg.PktTagType,
        PktTag:          nwCfg.PktTag,
        ExtPktTag:       nwCfg.ExtPktTag,
        GroupTag:        epgTag,
    }

    epgCfg.StateDriver = stateDriver
    epgCfg.ID = mastercfg.GetEndpointGroupKey(groupName, tenantName)
    log.Debugf("##Create EpGroup %v network %v tagtype %v", groupName, networkName, nwCfg.PktTagType)

    if len(ipPool) > 0 {
        // mark range as used
        netutils.SetIPAddrRange(&nwCfg.IPAllocMap, ipPool, nwCfg.SubnetIP, nwCfg.SubnetLen)

        if err := nwCfg.Write(); err != nil {
            return fmt.Errorf("updating epg ipaddress in network failed: %s", err)
        }
        netutils.InitSubnetBitset(&epgCfg.EPGIPAllocMap, nwCfg.SubnetLen)
        netutils.SetBitsOutsideRange(&epgCfg.EPGIPAllocMap, ipPool, nwCfg.SubnetLen)
    }
    return epgCfg.Write()
}

**netmaster/master/policy.go**

// PolicyAttach attaches a policy to an endpoint and adds associated rules to policyDB
func PolicyAttach(epg *contivModel.EndpointGroup, policy *contivModel.Policy) error {

    epgpKey := epg.Key + ":" + policy.Key

    stateDriver, err := utils.GetStateDriver()

    epgID, err := mastercfg.GetEndpointGroupID(stateDriver, epg.GroupName, epg.TenantName)

    // Create the epg policy
    gp, err = mastercfg.NewEpgPolicy(epgpKey, epgID, policy)
    if err != nil {
        log.Errorf("Error creating EPG policy. Err: %v", err)
        return err
    }

    return nil
}

**netmaster/mastercfg/policyState.go**

// NewEpgPolicy creates a new policy instance attached to an endpoint group
func NewEpgPolicy(epgpKey string, epgID int, policy *contivModel.Policy) (*EpgPolicy, error) {
    gp := new(EpgPolicy)
    gp.EpgPolicyKey = epgpKey
    gp.ID = epgpKey
    gp.EndpointGroupID = epgID
    gp.StateDriver = stateStore

    log.Infof("Creating new epg policy: %s", epgpKey)

    // init the dbs
    gp.RuleMaps = make(map[string]*RuleMap)

    // Install all rules within the policy
    for ruleKey := range policy.LinkSets.Rules {
        // find the rule
        rule := contivModel.FindRule(ruleKey)
        if rule == nil {
            log.Errorf("Error finding the rule %s", ruleKey)
            return nil, core.Errorf("rule not found")
        }

        log.Infof("Adding Rule %s to epgp policy %s", ruleKey, epgpKey)

        // Add the rule to epg Policy
        err := gp.AddRule(rule)
        if err != nil {
            log.Errorf("Error adding rule %s to epg polict %s. Err: %v", ruleKey, epgpKey, err)
            return nil, err
        }
    }

    // Save the policy state
    err := gp.Write()
    if err != nil {
        return nil, err
    }

    // Save it in local cache
    epgPolicyDb[epgpKey] = gp

    log.Info("Created epg policy {%+v}", gp)

    return gp, nil
}

**netmaster/mastercfg/policyState.go**

// AddRule adds a rule to epg policy
func (gp *EpgPolicy) AddRule(rule *contivModel.Rule) error {
    var dirs []string

    // Figure out all the directional rules we need to install
    switch rule.Direction {
    case "in":
        if (rule.Protocol == "udp" || rule.Protocol == "tcp") && rule.Port != 0 {
            dirs = []string{"inRx", "inTx"}
        } else {
            dirs = []string{"inRx"}
        }
    case "out":
        if (rule.Protocol == "udp" || rule.Protocol == "tcp") && rule.Port != 0 {
            dirs = []string{"outRx", "outTx"}
        } else {
            dirs = []string{"outTx"}
        }
    case "both":
        if (rule.Protocol == "udp" || rule.Protocol == "tcp") && rule.Port != 0 {
            dirs = []string{"inRx", "inTx", "outRx", "outTx"}
        } else {
            dirs = []string{"inRx", "outTx"}
        }

    }

    // create a ruleMap
    ruleMap := new(RuleMap)
    ruleMap.OfnetRules = make(map[string]*ofnet.OfnetPolicyRule)
    ruleMap.Rule = rule

    // Create ofnet rules
    for _, dir := range dirs {
        ofnetRule, err := gp.createOfnetRule(rule, dir)
        if err != nil {
            log.Errorf("Error creating %s ofnet rule for {%+v}. Err: %v", dir, rule, err)
            return err
        }

        // add it to the rule map
        ruleMap.OfnetRules[ofnetRule.RuleId] = ofnetRule
    }

    // save the rulemap
    gp.RuleMaps[rule.Key] = ruleMap

    return nil
}

// createOfnetRule creates a directional ofnet rule
func (gp *EpgPolicy) createOfnetRule(rule *contivModel.Rule, dir string) (*ofnet.OfnetPolicyRule, error) {
    var remoteEpgID int
    var err error

    ruleID := gp.EpgPolicyKey + ":" + rule.Key + ":" + dir

    // Create an ofnet rule
    ofnetRule := new(ofnet.OfnetPolicyRule)
    ofnetRule.RuleId = ruleID
    ofnetRule.Priority = rule.Priority
    ofnetRule.Action = rule.Action

    // See if user specified an endpoint Group in the rule
    if rule.FromEndpointGroup != "" {
        remoteEpgID, err = GetEndpointGroupID(stateStore, rule.FromEndpointGroup, rule.TenantName)
        if err != nil {
            log.Errorf("Error finding endpoint group %s/%s/%s. Err: %v",
                rule.FromEndpointGroup, rule.FromNetwork, rule.TenantName, err)
        }
    } else if rule.ToEndpointGroup != "" {
        remoteEpgID, err = GetEndpointGroupID(stateStore, rule.ToEndpointGroup, rule.TenantName)
        if err != nil {
            log.Errorf("Error finding endpoint group %s/%s/%s. Err: %v",
                rule.ToEndpointGroup, rule.ToNetwork, rule.TenantName, err)
        }
    } else if rule.FromNetwork != "" {
        netKey := rule.TenantName + ":" + rule.FromNetwork

        net := contivModel.FindNetwork(netKey)
        if net == nil {
            log.Errorf("Network %s not found", netKey)
            return nil, errors.New("the FromNetwork key wasn't found")
        }

        rule.FromIpAddress = net.Subnet
    } else if rule.ToNetwork != "" {
        netKey := rule.TenantName + ":" + rule.ToNetwork

        net := contivModel.FindNetwork(netKey)
        if net == nil {
            log.Errorf("Network %s not found", netKey)
            return nil, errors.New("the ToNetwork key wasn't found")
        }

        rule.ToIpAddress = net.Subnet
    }

    // Set protocol
    switch rule.Protocol {
    case "tcp":
        ofnetRule.IpProtocol = 6
    case "udp":
        ofnetRule.IpProtocol = 17
    case "icmp":
        ofnetRule.IpProtocol = 1
    case "igmp":
        ofnetRule.IpProtocol = 2
    case "":
        ofnetRule.IpProtocol = 0
    default:
        proto, err := strconv.Atoi(rule.Protocol)
        if err == nil && proto < 256 {
            ofnetRule.IpProtocol = uint8(proto)
        }
    }

    // Set directional parameters
    switch dir {
    case "inRx":
        // Set src/dest endpoint group
        ofnetRule.DstEndpointGroup = gp.EndpointGroupID
        ofnetRule.SrcEndpointGroup = remoteEpgID

        // Set src/dest IP Address
        ofnetRule.SrcIpAddr = rule.FromIpAddress
        if len(rule.ToIpAddress) > 0 {
            ofnetRule.DstIpAddr = rule.ToIpAddress
        }

        // set port numbers
        ofnetRule.DstPort = uint16(rule.Port)

        // set tcp flags
        if rule.Protocol == "tcp" && rule.Port == 0 {
            ofnetRule.TcpFlags = "syn,!ack"
        }
    case "inTx":
        // Set src/dest endpoint group
        ofnetRule.SrcEndpointGroup = gp.EndpointGroupID
        ofnetRule.DstEndpointGroup = remoteEpgID

        // Set src/dest IP Address
        ofnetRule.DstIpAddr = rule.FromIpAddress
        if len(rule.ToIpAddress) > 0 {
            ofnetRule.SrcIpAddr = rule.ToIpAddress
        }

        // set port numbers
        ofnetRule.SrcPort = uint16(rule.Port)
    case "outRx":
        // Set src/dest endpoint group
        ofnetRule.DstEndpointGroup = gp.EndpointGroupID
        ofnetRule.SrcEndpointGroup = remoteEpgID

        // Set src/dest IP Address
        ofnetRule.SrcIpAddr = rule.ToIpAddress

        // set port numbers
        ofnetRule.SrcPort = uint16(rule.Port)
    case "outTx":
        // Set src/dest endpoint group
        ofnetRule.SrcEndpointGroup = gp.EndpointGroupID
        ofnetRule.DstEndpointGroup = remoteEpgID

        // Set src/dest IP Address
        ofnetRule.DstIpAddr = rule.ToIpAddress

        // set port numbers
        ofnetRule.DstPort = uint16(rule.Port)

        // set tcp flags
        if rule.Protocol == "tcp" && rule.Port == 0 {
            ofnetRule.TcpFlags = "syn,!ack"
        }
    default:
        log.Fatalf("Unknown rule direction %s", dir)
    }

    // Add the Rule to policyDB
    err = ofnetMaster.AddRule(ofnetRule)
    if err != nil {
        log.Errorf("Error creating rule {%+v}. Err: %v", ofnetRule, err)
        return nil, err
    }

    // Send AddRule to netplugin agents
    err = addPolicyRuleState(ofnetRule)
    if err != nil {
        log.Errorf("Error creating rule {%+v}. Err: %v", ofnetRule, err)
        return nil, err
    }

    log.Infof("Added rule {%+v} to policyDB", ofnetRule)

    return ofnetRule, nil
}

**ofnet/ofnetMaster.go**

// AddRule adds a new rule to the policyDB
func (self *OfnetMaster) AddRule(rule *OfnetPolicyRule) error {

    // Publish it to all agents
    for nodeKey, node := range self.agentDb {

        client := rpcHub.Client(node.HostAddr, node.HostPort)
        err := client.Call("PolicyAgent.AddRule", rule, &resp)
    }

    return nil
}

**netmaster/mastercfg/policyRuleState.go**

// addPolicyRuleState adds policy rule to state store
func addPolicyRuleState(ofnetRule *ofnet.OfnetPolicyRule) error {
    ruleCfg := &CfgPolicyRule{}
    ruleCfg.StateDriver = stateStore
    ruleCfg.OfnetPolicyRule = (*ofnetRule)

    // Save the rule
    return ruleCfg.Write()
}

## netplugin 流程

### handleEpgEvents

**netplugin/agent/state_event.go**

func handleEpgEvents(netPlugin *plugin.NetPlugin, opts core.InstanceInfo, recvErr chan error) {

    rsps := make(chan core.WatchState)
    go processStateEvent(netPlugin, opts, rsps)
    cfg := mastercfg.EndpointGroupState{}
    cfg.StateDriver = netPlugin.StateDriver
    recvErr <- cfg.WatchAll(rsps)
    log.Errorf("Error from handleEpgEvents")
}

### processStateEvent

**netplugin/agent/state_event.go**

func processStateEvent(netPlugin *plugin.NetPlugin, opts core.InstanceInfo, rsps chan core.WatchState) {
    for {
        // block on change notifications
        rsp := <-rsps

        if epgCfg, ok := currentState.(*mastercfg.EndpointGroupState); ok {
            log.Infof("Received %q for Endpointgroup: %q", eventStr, epgCfg.EndpointGroupID)
            processEpgEvent(netPlugin, opts, epgCfg.ID, isDelete)
            continue
        }
    }
}

### processEpgEvent

**netplugin/agent/state_event.go**

func processEpgEvent(netPlugin *plugin.NetPlugin, opts core.InstanceInfo, ID string, isDelete bool) error {
    log.Infof("Received processEpgEvent")
    var err error

    operStr := ""
    if isDelete {
        operStr = "delete"
    } else {
        err = netPlugin.UpdateEndpointGroup(ID)
        operStr = "update"
    }
    if err != nil {
        log.Errorf("Epg %s failed. Error: %s", operStr, err)
    } else {
        log.Infof("Epg %s succeeded", operStr)
    }

    return err
}

**netplugin/plugin/netplugin.go**

//UpdateEndpointGroup updates the endpoint with the new endpointgroup specification for the given ID.
func (p *NetPlugin) UpdateEndpointGroup(id string) error {
    p.Lock()
    defer p.Unlock()
    return p.NetworkDriver.UpdateEndpointGroup(id)
}

**drivers/ovsd/ovsdriver.go**

//UpdateEndpointGroup updates the epg
func (d *OvsDriver) UpdateEndpointGroup(id string) error {
    log.Infof("Received endpoint group update for %s", id)
    var (
        err          error
        epgBandwidth int64
        sw           *OvsSwitch
    )
    //gets the EndpointGroupState object
    cfgEpGroup := &mastercfg.EndpointGroupState{}
    cfgEpGroup.StateDriver = d.oper.StateDriver
    err = cfgEpGroup.Read(id)

    if cfgEpGroup.ID != "" {
        if cfgEpGroup.Bandwidth != "" {
            epgBandwidth = netutils.ConvertBandwidth(cfgEpGroup.Bandwidth)
        }

        d.oper.localEpInfoMutex.Lock()
        defer d.oper.localEpInfoMutex.Unlock()
        for _, epInfo := range d.oper.LocalEpInfo {
            if epInfo.EpgKey == id {
                log.Debugf("Applying bandwidth: %s on: %s ", cfgEpGroup.Bandwidth, epInfo.Ovsportname)
                // Find the switch based on network type
                if epInfo.BridgeType == "vxlan" {
                    sw = d.switchDb["vxlan"]
                } else {
                    sw = d.switchDb["vlan"]
                }

                // update the endpoint in ovs switch
                err = sw.UpdateEndpoint(epInfo.Ovsportname, cfgEpGroup.Burst, cfgEpGroup.DSCP, epgBandwidth)
            }
        }
    }
    return err
}

**drivers/ovsd/ovsSwitch.go**

// UpdateEndpoint updates endpoint state
func (sw *OvsSwitch) UpdateEndpoint(ovsPortName string, burst, dscp int, epgBandwidth int64) error {
    // update bandwidth
    err := sw.ovsdbDriver.UpdatePolicingRate(ovsPortName, burst, epgBandwidth)

    // Get the openflow port number for the interface
    ofpPort, err := sw.ovsdbDriver.GetOfpPortNo(ovsPortName)

    // Build the updated endpoint info
    endpoint := ofnet.EndpointInfo{
        PortNo: ofpPort,
        Dscp:   dscp,
    }

    // update endpoint state in ofnet
    err = sw.ofnetAgent.UpdateLocalEndpoint(endpoint)

    return nil
}

**ofnet/ofnetAgent.go**

// UpdateLocalEndpoint update state on a local endpoint
func (self *OfnetAgent) UpdateLocalEndpoint(endpoint EndpointInfo) error {

    // find the local endpoint first
    epreg, _ := self.localEndpointDb.Get(string(endpoint.PortNo))

    ep := epreg.(*OfnetEndpoint)

    // pass it down to datapath
    err := self.datapath.UpdateLocalEndpoint(ep, endpoint)

    return nil
}

**ofnet/vlanBridge.go**

// UpdateLocalEndpoint update local endpoint state
func (vl *VlanBridge) UpdateLocalEndpoint(endpoint *OfnetEndpoint, epInfo EndpointInfo) error {
    oldDscp := endpoint.Dscp
    // Remove existing DSCP flows if required
    if epInfo.Dscp == 0 || epInfo.Dscp != endpoint.Dscp {
        // remove old DSCP flows
        dscpFlows, found := vl.dscpFlowDb[endpoint.PortNo]
        if found {
            for _, dflow := range dscpFlows {
                err := dflow.Delete()
            }
        }
    }

    // change DSCP value
    endpoint.Dscp = epInfo.Dscp

    // Add new DSCP flows if required
    if epInfo.Dscp != 0 && epInfo.Dscp != oldDscp {
        dNATTbl := vl.ofSwitch.GetTable(SRV_PROXY_DNAT_TBL_ID)

        // add new dscp flows
        dscpV4Flow, dscpV6Flow, err := createDscpFlow(vl.agent, vl.vlanTable, dNATTbl, endpoint)

        // save it for tracking
        vl.dscpFlowDb[endpoint.PortNo] = []*ofctrl.Flow{dscpV4Flow, dscpV6Flow}
    }

    return nil
}

# endpointgroup delete

```
NAME:
   netctl group rm - Delete an endpoint group

USAGE:
   netctl group rm [command options] [group]

OPTIONS:
   --tenant, -t "default"   Name of the tenant
```

![endpointgroup delete](epg-delete.png)

## netmaster 流程

**contivmodel/contivModel.go**

// DELETE rest call
func httpDeleteEndpointGroup(w http.ResponseWriter, r *http.Request, vars map[string]string) (interface{}, error) {
    log.Debugf("Received httpDeleteEndpointGroup: %+v", vars)

    key := vars["key"]

    // Delete the object
    err := DeleteEndpointGroup(key)

    // Return the obj
    return key, nil
}

// Delete a endpointGroup object
func DeleteEndpointGroup(key string) error {
    collections.endpointGroupMutex.Lock()
    obj := collections.endpointGroups[key]
    collections.endpointGroupMutex.Unlock()

    // Perform callback
    err := objCallbackHandler.EndpointGroupCb.EndpointGroupDelete(obj)

    // delete it from modeldb
    collections.endpointGroupMutex.Lock()
    err = obj.Delete()
    collections.endpointGroupMutex.Unlock()

    // delete it from cache
    collections.endpointGroupMutex.Lock()
    delete(collections.endpointGroups, key)
    collections.endpointGroupMutex.Unlock()

    return nil
}

**netmaster/objApi/apiController.go**

// EndpointGroupDelete deletes end point group
func (ac *APIController) EndpointGroupDelete(endpointGroup *contivModel.EndpointGroup) error {

    // if this is associated with an app profile, reject the delete
    if endpointGroup.Links.AppProfile.ObjKey != "" {
        return core.Errorf("Cannot delete %s, associated to appProfile %s",
            endpointGroup.GroupName, endpointGroup.Links.AppProfile.ObjKey)
    }

    // get the netprofile structure by finding the netprofile
    profileKey := GetNetprofileKey(endpointGroup.TenantName, endpointGroup.NetProfile)
    netprofile := contivModel.FindNetprofile(profileKey)

    if netprofile != nil {
        // Remove linksets from netprofile.
        modeldb.RemoveLinkSet(&netprofile.LinkSets.EndpointGroups, endpointGroup)
    }

    err := endpointGroupCleanup(endpointGroup)
    if err != nil {
        log.Errorf("EPG cleanup failed: %+v", err)
    }

    return err

}

// Cleans up state off endpointGroup and related objects.
func endpointGroupCleanup(endpointGroup *contivModel.EndpointGroup) error {
    // delete the endpoint group state
    err := master.DeleteEndpointGroup(endpointGroup.TenantName, endpointGroup.GroupName)

    // Detach the endpoint group from the Policies
    for _, policyName := range endpointGroup.Policies {
        policyKey := GetpolicyKey(endpointGroup.TenantName, policyName)

        // find the policy
        policy := contivModel.FindPolicy(policyKey)
        if policy == nil {
            log.Errorf("Could not find policy %s", policyName)
            continue
        }

        // detach policy to epg
        err := master.PolicyDetach(endpointGroup, policy)
        if err != nil && err != master.EpgPolicyExists {
            log.Errorf("Error detaching policy %s from epg %s", policyName, endpointGroup.Key)
        }

        // Remove links
        modeldb.RemoveLinkSet(&policy.LinkSets.EndpointGroups, endpointGroup)
        modeldb.RemoveLinkSet(&endpointGroup.LinkSets.Policies, policy)
        policy.Write()
    }

    // Cleanup any external contracts
    err = cleanupExternalContracts(endpointGroup)
    if err != nil {
        log.Errorf("Error cleaning up external contracts for epg %s", endpointGroup.Key)
    }

    // Remove the endpoint group from network and tenant link sets.
    nwObjKey := endpointGroup.TenantName + ":" + endpointGroup.NetworkName
    network := contivModel.FindNetwork(nwObjKey)
    if network != nil {
        modeldb.RemoveLinkSet(&network.LinkSets.EndpointGroups, endpointGroup)
        network.Write()
    }
    tenant := contivModel.FindTenant(endpointGroup.TenantName)
    if tenant != nil {
        modeldb.RemoveLinkSet(&tenant.LinkSets.EndpointGroups, endpointGroup)
        tenant.Write()
    }

    return nil
}

**netmaster/master/endpointGroup.go**

// DeleteEndpointGroup handles endpoint group deletes
func DeleteEndpointGroup(tenantName, groupName string) error {
    // Get the state driver
    stateDriver, err := utils.GetStateDriver()

    epgKey := mastercfg.GetEndpointGroupKey(groupName, tenantName)
    epgCfg := &mastercfg.EndpointGroupState{}
    epgCfg.StateDriver = stateDriver
    err = epgCfg.Read(epgKey)

    networkID := epgCfg.NetworkName + "." + epgCfg.TenantName
    nwCfg := &mastercfg.CfgNetworkState{}
    nwCfg.StateDriver = stateDriver
    err = nwCfg.Read(networkID)

    // Delete the endpoint group state
    gstate.GlobalMutex.Lock()
    defer gstate.GlobalMutex.Unlock()
    gCfg := gstate.Cfg{}
    gCfg.StateDriver = stateDriver
    err = gCfg.Read(epgCfg.TenantName)

    // Delete endpoint group
    err = epgCfg.Clear()
    if err != nil {
        log.Errorf("error writing epGroup config. Error: %v", err)
        return err
    }

    return nil
}

**netmaster/master/policy.go**

// PolicyDetach detaches policy from an endpoint and removes associated rules from policyDB
func PolicyDetach(epg *contivModel.EndpointGroup, policy *contivModel.Policy) error {

    epgpKey := epg.Key + ":" + policy.Key

    // find the policy
    gp := mastercfg.FindEpgPolicy(epgpKey)

    // Delete all rules within the policy
    for ruleKey := range policy.LinkSets.Rules {
        // find the rule
        rule := contivModel.FindRule(ruleKey)
        if rule == nil {
            log.Errorf("Error finding the rule %s", ruleKey)
            continue
        }

        log.Infof("Deleting Rule %s from epgp policy %s", ruleKey, epgpKey)

        // Add the rule to epg Policy
        err := gp.DelRule(rule)
        if err != nil {
            log.Errorf("Error deleting rule %s from epg polict %s. Err: %v", ruleKey, epgpKey, err)
        }
    }

    // delete it
    return gp.Delete()
}

**netmaster/mastercfg/policyState.go**

// DelRule removes a rule from epg policy
func (gp *EpgPolicy) DelRule(rule *contivModel.Rule) error {
    // check if the rule exists
    ruleMap := gp.RuleMaps[rule.Key]

    // Delete each ofnet rule under this policy rule
    for _, ofnetRule := range ruleMap.OfnetRules {
        log.Infof("Deleting rule {%+v} from policyDB", ofnetRule)

        // Delete the rule from policyDB
        err := ofnetMaster.DelRule(ofnetRule)

        // Send DelRule to netplugin agents
        err = delPolicyRuleState(ofnetRule)
    }

    // delete the cache
    delete(gp.RuleMaps, rule.Key)

    return nil
}

**ofnet/ofnetMaster.go**

// DelRule removes a rule from policy DB
func (self *OfnetMaster) DelRule(rule *OfnetPolicyRule) error {

    // Remove the rule from DB
    self.masterMutex.Lock()
    delete(self.policyDb, rule.RuleId)
    self.masterMutex.Unlock()

    // take a read lock for accessing db
    self.masterMutex.RLock()
    defer self.masterMutex.RUnlock()

    // Publish it to all agents
    for nodeKey, node := range self.agentDb {
        var resp bool

        log.Infof("Sending DELETE rule: %+v to node %s", rule, node.HostAddr)

        client := rpcHub.Client(node.HostAddr, node.HostPort)
        err := client.Call("PolicyAgent.DelRule", rule, &resp)
        if err != nil {
            log.Errorf("Error adding rule to %s. Err: %v", node.HostAddr, err)
            // Continue sending the message to other nodes

            // increment stats
            self.incrAgentStats(nodeKey, "DelRuleFailure")
        } else {
            // increment stats
            self.incrAgentStats(nodeKey, "DelRuleSent")
        }
    }

    return nil
}

**netmaster/mastercfg/policyRuleState.go**

// delPolicyRuleState deletes policy rule from state store
func delPolicyRuleState(ofnetRule *ofnet.OfnetPolicyRule) error {
    ruleCfg := &CfgPolicyRule{}
    ruleCfg.StateDriver = stateStore
    ruleCfg.OfnetPolicyRule = (*ofnetRule)

    // Delete the rule
    return ruleCfg.Clear()
}

## netplugin 流程

### handleEpgEvents

**agent/state_event.go**

func handleEpgEvents(netPlugin *plugin.NetPlugin, opts core.InstanceInfo, recvErr chan error) {

    rsps := make(chan core.WatchState)
    go processStateEvent(netPlugin, opts, rsps)
    cfg := mastercfg.EndpointGroupState{}
    cfg.StateDriver = netPlugin.StateDriver
    recvErr <- cfg.WatchAll(rsps)
    log.Errorf("Error from handleEpgEvents")
}

### processStateEvent 处理 EndpointGroupState 事件

**netplugin/agent/state_event.go**

func processStateEvent(netPlugin *plugin.NetPlugin, opts core.InstanceInfo, rsps chan core.WatchState) {
    for {
        // block on change notifications
        rsp := <-rsps

        // For now we deal with only create and delete events
        currentState := rsp.Curr
        isDelete := false
        eventStr := "create"
        if rsp.Curr == nil {
            currentState = rsp.Prev
            isDelete = true
            eventStr = "delete"
        } else if rsp.Prev != nil {

        }

        if epgCfg, ok := currentState.(*mastercfg.EndpointGroupState); ok {
            log.Infof("Received %q for Endpointgroup: %q", eventStr, epgCfg.EndpointGroupID)
            processEpgEvent(netPlugin, opts, epgCfg.ID, isDelete)
            continue
        }
    }
}

### processEpgEvent

**netplugin/agent/state_event.go**

func processEpgEvent(netPlugin *plugin.NetPlugin, opts core.InstanceInfo, ID string, isDelete bool) error {
    log.Infof("Received processEpgEvent")
    var err error

    operStr := ""
    if isDelete {
        operStr = "delete"
    } else {
    }

    return err
}

