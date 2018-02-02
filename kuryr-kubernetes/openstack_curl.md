<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Set openrc](#set-openrc)
- [Get keystone token](#get-keystone-token)
- [Export OS_TOKEN](#export-os_token)
- [Test: get gbp l3_policies from neutron](#test-get-gbp-l3_policies-from-neutron)
- [Test: get projects from keystone](#test-get-projects-from-keystone)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Set openrc

```
export OS_USER_DOMAIN_ID=default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_ID=default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USERNAME=admin
export OS_PROJECT_NAME=admin
export OS_PASSWORD=devops
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
export OS_AUTH_URL=http://controller:35357/v3
```

# Get keystone token

```bash
curl -v -s -X POST $OS_AUTH_URL/auth/tokens?nocatalog -H "Content-Type: application/json" -d '{ "auth": { "identity": { "methods": ["password"],"password": {"user": {"domain": {"name": "'"$OS_USER_DOMAIN_NAME"'"},"name": "'"$OS_USERNAME"'", "password": "'"$OS_PASSWORD"'"} } }, "scope": { "project": { "domain": { "name": "'"$OS_PROJECT_DOMAIN_NAME"'" }, "name":  "'"$OS_PROJECT_NAME"'" } } }}' | python -m json.tool
```

result:

```
* About to connect() to controller port 35357 (#0)
*   Trying 192.168.16.19...
* Connected to controller (192.168.16.19) port 35357 (#0)
> POST /v3/auth/tokens?nocatalog HTTP/1.1
> User-Agent: curl/7.29.0
> Host: controller:35357
> Accept: */*
> Content-Type: application/json
> Content-Length: 226
> 
} [data not shown]
* upload completely sent off: 226 out of 226 bytes
< HTTP/1.1 201 Created
< Date: Tue, 07 Nov 2017 12:28:05 GMT
< Server: Apache/2.4.6 (CentOS) OpenSSL/1.0.1e-fips mod_fcgid/2.3.9 mod_wsgi/3.4 Python/2.7.5
< X-Subject-Token: gAAAAABaAabV3oYQAfwO9HixHcNkXstwYO8uOvtrrXzUby3t8KyoPhwjJrcZujFxk1lkUVrQxAUpefvRztuX-CIxAumzPRChSiPi8khNdG70iawv8I4ljngMl_ItbMa3yqAVOgP1icJiah_-vbk_o_iGJG5HRPAXRJVsFK6x24rqApm52uv99ig
< Vary: X-Auth-Token
< x-openstack-request-id: req-c6654347-645d-4ead-9e29-a1abab1adc38
< Content-Length: 524
< Content-Type: application/json
< 
{ [data not shown]
* Connection #0 to host controller left intact
{
    "token": {
        "audit_ids": [
            "E1xIWBo9QuCPWddJvYbyvg"
        ],
        "expires_at": "2017-11-07T13:28:05.000000Z",
        "is_domain": false,
        "issued_at": "2017-11-07T12:28:05.000000Z",
        "methods": [
            "password"
        ],
        "project": {
            "domain": {
                "id": "default",
                "name": "Default"
            },
            "id": "0d20a1743c0c40069d29250352caea88",
            "name": "admin"
        },
        "roles": [
            {
                "id": "9a7ee3df9ef24b3a92206b4c1f2c0541",
                "name": "admin"
            }
        ],
        "user": {
            "domain": {
                "id": "default",
                "name": "Default"
            },
            "id": "47ea6c809d794c239314a9b9ae733b50",
            "name": "admin",
            "password_expires_at": null
        }
    }
}
```

# Export OS_TOKEN

```
export OS_TOKEN=gAAAAABaAabV3oYQAfwO9HixHcNkXstwYO8uOvtrrXzUby3t8KyoPhwjJrcZujFxk1lkUVrQxAUpefvRztuX-CIxAumzPRChSiPi8khNdG70iawv8I4ljngMl_ItbMa3yqAVOgP1icJiah_-vbk_o_iGJG5HRPAXRJVsFK6x24rqApm52uv99ig
```

# Test: get gbp l3_policies from neutron

```bash
curl -s -H "X-Auth-Token: $OS_TOKEN" -X GET http://controller:9696/v2.0/grouppolicy/l3_policies | python -m json.tool
```

result:

```json
{
    "l3_policies": [
        {
            "address_scope_v4_id": "29254c88-5ff8-4083-8ac3-c1df65dafa38",
            "address_scope_v6_id": null,
            "description": "",
            "external_segments": {},
            "id": "8b2d649b-fbbd-40ef-ae76-7c4202b33552",
            "ip_pool": "10.0.0.0/8",
            "ip_version": 4,
            "l2_policies": [
                "449c0534-291c-48b0-bcec-158a83a83c14",
                "5e7e2e0c-acb9-4759-b059-4269b312687d",
                "c2f412fc-d412-4ecd-b443-9b72b72bea4f"
            ],
            "name": "default",
            "project_id": "0d20a1743c0c40069d29250352caea88",
            "proxy_ip_pool": "192.168.0.0/16",
            "proxy_subnet_prefix_length": 28,
            "routers": [
                "77e5b909-6038-407b-9ab7-f80bd6b8c637"
            ],
            "shared": false,
            "status": null,
            "status_details": null,
            "subnet_prefix_length": 24,
            "subnetpools_v4": [
                "adea3e09-8537-405c-99f7-8cd9310f2ffb"
            ],
            "subnetpools_v6": [],
            "tenant_id": "0d20a1743c0c40069d29250352caea88"
        }
    ]
}
```

# Test: get projects from keystone

```bash
curl -s -H "X-Auth-Token: $OS_TOKEN" -X GET http://controller:35357/v3/projects | python -m json.tool
```

result:

```json
{
    "links": {
        "next": null,
        "previous": null,
        "self": "http://controller:35357/v3/projects"
    },
    "projects": [
        {
            "description": "Bootstrap project for initializing the cloud.",
            "domain_id": "default",
            "enabled": true,
            "id": "0d20a1743c0c40069d29250352caea88",
            "is_domain": false,
            "links": {
                "self": "http://controller:35357/v3/projects/0d20a1743c0c40069d29250352caea88"
            },
            "name": "admin",
            "parent_id": "default"
        },
        {
            "description": "UnionPay",
            "domain_id": "default",
            "enabled": true,
            "id": "22acf7eff1e246ffba05639c235ee958",
            "is_domain": false,
            "links": {
                "self": "http://controller:35357/v3/projects/22acf7eff1e246ffba05639c235ee958"
            },
            "name": "caicloud",
            "parent_id": "default"
        },
        {
            "description": "Service Project",
            "domain_id": "default",
            "enabled": true,
            "id": "29d9dd9e47f847f0b40a23ff2295090c",
            "is_domain": false,
            "links": {
                "self": "http://controller:35357/v3/projects/29d9dd9e47f847f0b40a23ff2295090c"
            },
            "name": "service",
            "parent_id": "default"
        },
        {
            "description": "Demo Project",
            "domain_id": "default",
            "enabled": true,
            "id": "6050921740584beea0a8cd7fbd2f4ed9",
            "is_domain": false,
            "links": {
                "self": "http://controller:35357/v3/projects/6050921740584beea0a8cd7fbd2f4ed9"
            },
            "name": "demo",
            "parent_id": "default"
        }
    ]
}
```




