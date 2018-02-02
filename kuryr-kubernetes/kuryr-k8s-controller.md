<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Service yaml](#service-yaml)
- [Endpoint yaml](#endpoint-yaml)
- [<h1 id="1">1. kuryr-k8s-controller</h1>](#h1-id11-kuryr-k8s-controllerh1)
  - [<h2 id="1.1">1.1. KuryrK8sService</h2>](#h2-id1111-kuryrk8sserviceh2)
    - [<h3 id="1.1.1">1.1.1. ControllerPipeline</h3>](#h3-id111111-controllerpipelineh3)
      - [<h4 id="1.1.1.1">1.1.1.1. Retry</h4>](#h4-id11111111-retryh4)
      - [<h4 id="1.1.1.2">1.1.1.2. Async</h4>](#h4-id11121112-asynch4)
    - [<h3 id="1.1.2">1.1.2. VIFHandler</h3>](#h3-id112112-vifhandlerh3)
    - [<h3 id="1.1.3">1.1.3. LBaaSSpecHandler</h3>](#h3-id113113-lbaasspechandlerh3)
    - [<h3 id="1.1.4">1.1.4. LoadBalancerHandler</h3>](#h3-id114114-loadbalancerhandlerh3)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

* [1. kuryr-k8s-controller](#1)
    * [1.1. KuryrK8sService](#1.1)
        * [1.1.1. ControllerPipeline](#1.1.1)
            * [1.1.1.1. Retry](#1.1.1.1)
            * [1.1.1.2. Async](#1.1.1.2)
        * [1.1.2. VIFHandler](#1.1.2)
        * [1.1.3. LBaaSSpecHandler](#1.1.3)
        * [1.1.4. LoadBalancerHandler](#1.1.4)

# Service yaml

```yaml
apiVersion: v1
kind: Service
metadata:
   annotations:
     openstack.org/kuryr-lbaas-spec: '{"versioned_object.data": {"ip": "10.20.79.53",
       "ports": [{"versioned_object.data": {"name": null, "port": 82, "protocol": "TCP"},
       "versioned_object.name": "LBaaSPortSpec", "versioned_object.namespace": "kuryr_kubernetes",
       "versioned_object.version": "1.0"}], "project_id": "22acf7eff1e246ffba05639c235ee958",
       "security_groups_ids": ["0cc213ea-d286-4a9f-aa3a-c629e49ea807"], "subnet_id":
       "5fb9bf5e-06aa-419e-88bd-15bca4b0f564"}, "versioned_object.name": "LBaaSServiceSpec",
       "versioned_object.namespace": "kuryr_kubernetes", "versioned_object.version":
       "1.0"}'
  creationTimestamp: 2017-08-25T08:27:33Z
  labels:
    name: nginx-service
  name: nginx-service
  namespace: default
  resourceVersion: "359595"
  selfLink: /api/v1/namespaces/default/services/nginx-service
  uid: 3e609f14-896f-11e7-a2a1-ac1f6b1274fa
spec:
  clusterIP: 10.20.79.53
  ports:
  - port: 82
    protocol: TCP
    targetPort: 80
  selector:
    app: nginx
  sessionAffinity: None
  type: ClusterIP
status:
  loadBalancer: {}
```

# Endpoint yaml

```yaml
apiVersion: v1
kind: Endpoints
metadata:
  annotations:
    openstack.org/kuryr-lbaas-spec: '{"versioned_object.data": {"ip": "10.20.79.53",
      "ports": [{"versioned_object.data": {"name": null, "port": 82, "protocol": "TCP"},
      "versioned_object.name": "LBaaSPortSpec", "versioned_object.namespace": "kuryr_kubernetes",
      "versioned_object.version": "1.0"}], "project_id": "22acf7eff1e246ffba05639c235ee958",
      "security_groups_ids": ["0cc213ea-d286-4a9f-aa3a-c629e49ea807"], "subnet_id":
      "5fb9bf5e-06aa-419e-88bd-15bca4b0f564"}, "versioned_object.name": "LBaaSServiceSpec",
      "versioned_object.namespace": "kuryr_kubernetes", "versioned_object.version":
      "1.0"}'
    openstack.org/kuryr-lbaas-state: '{"versioned_object.data": {"listeners": [{"versioned_object.data":
      {"id": "c8ec2bb3-662b-4558-b835-b8398b3c650c", "loadbalancer_id": "bbb7464e-6a6a-46da-b383-82af1a9affc4",
      "name": "default/nginx-service:TCP:82", "port": 82, "project_id": "22acf7eff1e246ffba05639c235ee958",
      "protocol": "TCP"}, "versioned_object.name": "LBaaSListener", "versioned_object.namespace":
      "kuryr_kubernetes", "versioned_object.version": "1.0"}], "loadbalancer": {"versioned_object.data":
      {"id": "bbb7464e-6a6a-46da-b383-82af1a9affc4", "ip": "10.20.79.53", "name":
      "default/nginx-service", "project_id": "22acf7eff1e246ffba05639c235ee958", "subnet_id":
      "5fb9bf5e-06aa-419e-88bd-15bca4b0f564"}, "versioned_object.name": "LBaaSLoadBalancer",
      "versioned_object.namespace": "kuryr_kubernetes", "versioned_object.version":
      "1.0"}, "members": [{"versioned_object.data": {"id": "60238fb2-dd0a-4ae2-919c-fde1e1745a25",
      "ip": "10.10.1.11", "name": "default/nginx-1x49s:80", "pool_id": "8a3451f3-85d4-48bc-b892-62d27b8a590f",
      "port": 80, "project_id": "22acf7eff1e246ffba05639c235ee958", "subnet_id": "5fb9bf5e-06aa-419e-88bd-15bca4b0f564"},
      "versioned_object.name": "LBaaSMember", "versioned_object.namespace": "kuryr_kubernetes",
      "versioned_object.version": "1.0"}], "pools": [{"versioned_object.data": {"id":
      "8a3451f3-85d4-48bc-b892-62d27b8a590f", "listener_id": "c8ec2bb3-662b-4558-b835-b8398b3c650c",
      "loadbalancer_id": "bbb7464e-6a6a-46da-b383-82af1a9affc4", "name": "default/nginx-service:TCP:82",
      "project_id": "22acf7eff1e246ffba05639c235ee958", "protocol": "TCP"}, "versioned_object.name":
      "LBaaSPool", "versioned_object.namespace": "kuryr_kubernetes", "versioned_object.version":
      "1.0"}]}, "versioned_object.name": "LBaaSState", "versioned_object.namespace":
      "kuryr_kubernetes", "versioned_object.version": "1.0"}'
  creationTimestamp: 2017-08-25T08:27:33Z
  labels:
    name: nginx-service
  name: nginx-service
  namespace: default
  resourceVersion: "933638"
  selfLink: /api/v1/namespaces/default/endpoints/nginx-service
  uid: 3e6434f4-896f-11e7-a2a1-ac1f6b1274fa
subsets:
- addresses:
  - ip: 10.10.1.11
    nodeName: computer2
    targetRef:
      kind: Pod
      name: nginx-1x49s
      namespace: default
      resourceVersion: "933636"
      uid: 458d0618-8dee-11e7-a2a1-ac1f6b1274fa
  ports:
  - port: 80
    protocol: TCP
```

# <h1 id="1">1. kuryr-k8s-controller</h1>

```
# setup.cfg
[entry_points]
console_scripts =
    kuryr-k8s-controller = kuryr_kubernetes.cmd.eventlet.controller:start
    kuryr-cni = kuryr_kubernetes.cmd.cni:run
```

`kuryr-k8s-controller` 的执行的是 `kuryr-kubernetes/cmd/eventlet/controller.py: start()` 函数:

```
# kuryr-kubernetes/cmd/eventlet/controller.py
from kuryr_kubernetes.controller import service

start = service.start

if __name__ == '__main__':
    start()
```

```
# kuryr-kubernetes/controller/service.py
def start():
    config.init(sys.argv[1:])
    config.setup_logging()
    clients.setup_clients()
    os_vif.initialize()
    # 以线程方式启动服务
    kuryrk8s_launcher = service.launch(config.CONF, KuryrK8sService())
    # 等待服务结束
    kuryrk8s_launcher.wait()
```

`clients.setup_clients()` 主要创建 `neutron client` 和 `k8s client`:

```
# kuryr-kubernetes/clients.py
def setup_clients():
    setup_neutron_client()
    setup_kubernetes_client()
```

下面看看 `service.launch()`:

```
# openstack/oslo.service/oslo_service/service.py
def launch(conf, service, workers=1, restart_method='reload'):
    """Launch a service with a given number of workers.
    :param conf: an instance of ConfigOpts
    :param service: a service to launch, must be an instance of
           :class:`oslo_service.service.ServiceBase`
    :param workers: a number of processes in which a service will be running
    :param restart_method: Passed to the constructed launcher. If 'reload', the
        launcher will call reload_config_files on SIGHUP. If 'mutate', it will
        call mutate_config_files on SIGHUP. Other values produce a ValueError.
    :returns: instance of a launcher that was used to launch the service
    """

    if workers is not None and workers <= 0:
        raise ValueError(_("Number of workers should be positive!"))

    if workers is None or workers == 1:
        launcher = ServiceLauncher(conf, restart_method=restart_method)
    else:
        launcher = ProcessLauncher(conf, restart_method=restart_method)
    launcher.launch_service(service, workers=workers)

    return launcher
```

所以, `KuryrK8sService` 也直接或者间接继承和实现了 `ServiceBase` 类方法, 而实际上 `KuryrK8sService` 继承了 `Service` 类:

```
# openstack/oslo.service/oslo_service/service.py
@six.add_metaclass(abc.ABCMeta)
class ServiceBase(object):
    """Base class for all services."""

    @abc.abstractmethod
    def start(self):
        """Start service."""

    @abc.abstractmethod
    def stop(self):
        """Stop service."""

    @abc.abstractmethod
    def wait(self):
        """Wait for service to complete."""

    @abc.abstractmethod
    def reset(self):
        """Reset service.
        Called in case service running in daemon mode receives SIGHUP.
        """

class Service(ServiceBase):
    """Service object for binaries running on hosts."""

    def __init__(self, threads=1000):
        self.tg = threadgroup.ThreadGroup(threads)

    def reset(self):
        """Reset a service in case it received a SIGHUP."""

    def start(self):
        """Start a service."""

    def stop(self, graceful=False):
        """Stop a service.
        :param graceful: indicates whether to wait for all threads to finish
               or terminate them instantly
        """
        self.tg.stop(graceful)

    def wait(self):
        """Wait for a service to shut down."""
        self.tg.wait()
```

## <h2 id="1.1">1.1. KuryrK8sService</h2>

```
# openstack/oslo.service/oslo_service/service.py
class KuryrK8sService(service.Service):
    """Kuryr-Kubernetes controller Service."""

    def __init__(self):
        super(KuryrK8sService, self).__init__()

        objects.register_locally_defined_vifs()
        pipeline = h_pipeline.ControllerPipeline(self.tg)
        self.watcher = watcher.Watcher(pipeline, self.tg)
        # TODO(ivc): pluggable resource/handler registration
        # Controller watches pods, services and endpoints
        for resource in ["pods", "services", "endpoints"]:
            self.watcher.add("%s/%s" % (constants.K8S_API_BASE, resource))
        # pod event handler
        # 注册 consumer
        pipeline.register(h_vif.VIFHandler())
        # service event handler
        # 注册 consumer
        pipeline.register(h_lbaas.LBaaSSpecHandler())
        # endpoint event handler
        # 注册 consumer
        pipeline.register(h_lbaas.LoadBalancerHandler())

    def start(self):
        LOG.info("Service '%s' starting", self.__class__.__name__)
        super(KuryrK8sService, self).start()
        self.watcher.start()
        LOG.info("Service '%s' started", self.__class__.__name__)

    def wait(self):
        super(KuryrK8sService, self).wait()
        LOG.info("Service '%s' stopped", self.__class__.__name__)

    def stop(self, graceful=False):
        LOG.info("Service '%s' stopping", self.__class__.__name__)
        self.watcher.stop()
        super(KuryrK8sService, self).stop(graceful)
```

### <h3 id="1.1.1">1.1.1. ControllerPipeline</h3>

```
# kuryr-kubernetes/kuryr_kubernetes/handlers/k8s_base.py
def object_link(event):
    try:
        return event['object']['metadata']['selfLink']
    except KeyError:
        return None

# kuryr-kubernetes/controller/handlers/pipeline.py
class ControllerPipeline(h_dis.EventPipeline):
    """Serves as an entry point for controller Kubernetes events.

    `ControllerPipeline` is an entry point handler for the Kuryr-Kubernetes
    controller. `ControllerPipeline` allows registering
    :class:`kuryr_kubernetes.handlers.k8s_base.ResourceEventHandler`s and
    ensures the proper handler is called for each event that is passed to the
    `ControllerPipeline`. Also it ensures the following behavior:

      - multiple `ResourceEventHandler`s can be registered for the same
        resource type (`OBJECT_KIND`)

      - failing handlers (i.e. ones that raise `Exception`s) are retried
        until either the handler succeeds or a finite amount of time passes,
        in which case the most recent exception is logged

      - in case there are multiple handlers registered for the same resource
        type, all such handlers are considered independent (i.e. if one
        handler fails, other handlers will still be called regardless; and the
        order in which such handlers are called is not determined)

      - events for different Kubernetes objects can be handled concurrently

      - events for the same Kubernetes object are handled sequentially in
        the order of arrival
    """

    def __init__(self, thread_group):
        self._tg = thread_group
        super(ControllerPipeline, self).__init__()

    def _wrap_consumer(self, consumer):
        # TODO(ivc): tune retry interval/timeout
        return h_log.LogExceptions(h_retry.Retry(
            consumer, exceptions=exceptions.ResourceNotReady))

    def _wrap_dispatcher(self, dispatcher):
        # object_link is group_by function
        # 同一个 k8s object 的 event 在同一个 group
        return h_log.LogExceptions(h_async.Async(dispatcher, self._tg,
                                                 h_k8s.object_link))

# kuryr-kubernetes/controller/handlers/logging.py
class LogExceptions(base.EventHandler):
    """Suppresses exceptions and sends them to log.

    LogExceptions wraps `handler` passed as an initialization parameter by
    suppressing `exceptions` it raises and sending them to logging facility
    instead.
    """

    def __init__(self, handler, exceptions=Exception):
        self._handler = handler
        self._exceptions = exceptions

    def __call__(self, event):
        try:
            self._handler(event)
        except self._exceptions:
            LOG.exception("Failed to handle event %s", event)

# kuryr-kubernetes/kuryr-kubernetes/handlers/dispatch.py
@six.add_metaclass(abc.ABCMeta)
class EventPipeline(h_base.EventHandler):
    """Serves as an entry-point for event handling.

    Implementing subclasses should override `_wrap_dispatcher` and/or
    `_wrap_consumer` methods to sanitize the consumers passed to `register`
    (i.e. to satisfy the `Watcher` requirement that the event handler does
    not raise exceptions) and to add features like asynchronous event
    processing or retry-on-failure functionality.
    """

    def __init__(self):
        self._dispatcher = Dispatcher()
        self._handler = self._wrap_dispatcher(self._dispatcher)

    def register(self, consumer):
        """Adds handler to the registry.

        :param consumer: `EventConsumer`-type object
        """
        handler = self._wrap_consumer(consumer)
        for key_fn, key in consumer.consumes.items():
            self._dispatcher.register(key_fn, key, handler)

    def __call__(self, event):
        self._handler(event)

    @abc.abstractmethod
    def _wrap_dispatcher(self, dispatcher):
        raise NotImplementedError()

    @abc.abstractmethod
    def _wrap_consumer(self, consumer):
        raise NotImplementedError()
```

`ControllerPipeline` 的类继承关系如下:

`ControllerPipeline <- EventPipeline <- EventHandler`

`ControllerPipeline` 通过 `_wrap_consumer` 对 `Async dispacher` 进行了封装. 

`ControllerPipeline` 通过 `_wrap_dispatcher` 对 `Retry consumer` 进行了封装.

而 `Retry` 封装了 `VIFHandler`, `LBaaSSpecHandler` 和 `LoadBalancerHandler` 这三个 `consumer`, 而 `Async` 封装了 `Dispacher`.

而 `LogExceptions` 实现对 `Retry` 和 `Async` 的封装.

#### <h4 id="1.1.1.1">1.1.1.1. Retry</h4>

```
# kuryr-kubernetes/controller/handlers/retry.py
# 封装 consumer
class Retry(base.EventHandler):
    """Retries handler on failure.

    `Retry` can be used to decorate another `handler` to be retried whenever
    it raises any of the specified `exceptions`. If the `handler` does not
    succeed within the time limit specified by `timeout`, `Retry` will
    raise the exception risen by `handler`. `Retry` does not interrupt the
    `handler`, so the actual time spent within a single call to `Retry` may
    exceed the `timeout` depending on responsiveness of the `handler`.

    `Retry` implements a variation of exponential backoff algorithm [1] and
    ensures that there is a minimal time `interval` after the failed
    `handler` is retried for the same `event` (expected backoff E(c) =
    interval * 2 ** c / 2).

    [1] https://en.wikipedia.org/wiki/Exponential_backoff
    """

    def __init__(self, handler, exceptions=Exception,
                 timeout=DEFAULT_TIMEOUT, interval=DEFAULT_INTERVAL):
        self._handler = handler
        self._exceptions = exceptions
        self._timeout = timeout
        self._interval = interval

    def __call__(self, event):
        deadline = time.time() + self._timeout
        # itertools.count(1) --> 1, 2, 3, 4, ...
        for attempt in itertools.count(1):
            try:
                self._handler(event)
                break
            except self._exceptions:
                with excutils.save_and_reraise_exception() as ex:
                    if self._sleep(deadline, attempt, ex.value):
                        ex.reraise = False

    def _sleep(self, deadline, attempt, exception):
        now = time.time()
        seconds_left = deadline - now

        if seconds_left <= 0:
            LOG.debug("Handler %s failed (attempt %s; %s), "
                      "timeout exceeded (%s seconds)",
                      self._handler, attempt, exceptions.format_msg(exception),
                      self._timeout)
            return 0

        interval = random.randint(1, 2 ** attempt - 1) * self._interval

        if interval > seconds_left:
            interval = seconds_left

        if interval < self._interval:
            interval = self._interval

        LOG.debug("Handler %s failed (attempt %s; %s), "
                  "retrying in %s seconds",
                  self._handler, attempt, exceptions.format_msg(exception),
                  interval)

        time.sleep(interval)
        return interval
```

通过 `Retry` 的封装, 被封装的 `consumer` 只要处理 `event` 失败就会一直 `retry to deal with the event`.

#### <h4 id="1.1.1.2">1.1.1.2. Async</h4>

```
# kuryr-kubernetes/controller/handlers/asynchronous.py
DEFAULT_QUEUE_DEPTH = 100
DEFAULT_GRACE_PERIOD = 5

# 封装 Dispatcher
# 通过 group_by fucn 使得不同的 object 位于不同的 group, 每个 group 用于一个独立的队列
# 不同的 group, Async 会创建不同的线程, 用 Dispatcher 对象函数 (__call__) 去分发 event
class Async(base.EventHandler):
    """Handles events asynchronously.

    `Async` can be used to decorate another `handler` to be run asynchronously
    using the specified `thread_group`. `Async` distinguishes *related* and
    *unrelated* events (based on the result of `group_by`(`event`) function)
    and handles *unrelated* events concurrently while *related* events are
    handled serially and in the same order they arrived to `Async`.
    """

    def __init__(self, handler, thread_group, group_by,
                 queue_depth=DEFAULT_QUEUE_DEPTH,
                 grace_period=DEFAULT_GRACE_PERIOD):
        self._handler = handler
        self._thread_group = thread_group
        # group_by function 
        self._group_by = group_by
        self._queue_depth = queue_depth
        self._grace_period = grace_period
        self._queues = {}

    def __call__(self, event):
        group = self._group_by(event)
        try:
            queue = self._queues[group]
        except KeyError:
            queue = six_queue.Queue(self._queue_depth)
            self._queues[group] = queue
            thread = self._thread_group.add_thread(self._run, group, queue)
            # Set up a function to be called with the results of the GreenThread
            thread.link(self._done, group)
        # 线程已经起来, 把 event 放入 queue, 等待线程处理
        queue.put(event)

    def _run(self, group, queue):
        LOG.debug("Asynchronous handler started processing %s", group)
        for _ in itertools.count():
            # NOTE(ivc): this is a mock-friendly replacement for 'while True'
            # to allow more controlled environment for unit-tests (e.g. to
            # avoid tests getting stuck in infinite loops)
            try:
                event = queue.get(timeout=self._grace_period)
            # 如果 timeout 之后 queue 还是 Empty, 那么线程就退出
            except six_queue.Empty:
                break
            # FIXME(ivc): temporary workaround to skip stale events
            # If K8s updates resource while the handler is processing it,
            # when the handler finishes its work it can fail to update an
            # annotation due to the 'resourceVersion' conflict. K8sClient
            # was updated to allow *new* annotations to be set ignoring
            # 'resourceVersion', but it leads to another problem as the
            # Handler will receive old events (i.e. before annotation is set)
            # and will start processing the event 'from scratch'.
            # It has negative effect on handlers' performance (VIFHandler
            # creates ports only to later delete them and LBaaS handler also
            # produces some excess requests to Neutron, although with lesser
            # impact).
            # Possible solutions (can be combined):
            #  - use K8s ThirdPartyResources to store data/annotations instead
            #    of native K8s resources (assuming Kuryr-K8s will own those
            #    resources and no one else would update them)
            #  - use the resulting 'resourceVersion' received from K8sClient's
            #    'annotate' to provide feedback to Async to skip all events
            #    until that version
            #  - stick to the 'get-or-create' behaviour in handlers and
            #    also introduce cache for long operations
            time.sleep(STALE_PERIOD)
            # 当 k8s 在更新资源的时候, 如果 handler 在更新 annotation, 会导致资源版本冲突
            # 为避免这种情况的发生, 使用资源最终结果版本, 过滤掉之前所有的版本
            while not queue.empty():
                event = queue.get()
                if queue.empty():
                    time.sleep(STALE_PERIOD)
            # consumer 处理 event
            self._handler(event)

    def _done(self, thread, group):
        LOG.debug("Asynchronous handler stopped processing %s", group)
        queue = self._queues.pop(group)

        if not queue.empty():
            LOG.critical("Asynchronous handler terminated abnormally; "
                         "%(count)s events dropped for %(group)s",
                         {'count': queue.qsize(), 'group': group})

        if not self._queues:
            LOG.debug("Asynchronous handler is idle")
```

通过 `Async` 的封装, 能保证一下几点:

- 不同 `k8s object` 的 `event` 位于不同的  `queue` 中
- 不同 `k8s object` 的 `queue` 中的 `event` 将在不同的线程中调用 `Dispatcher: __call__()` 去分发 `event` 到 `consumer`
- 避免 k8s 和 `consumer` 同时更新 `k8s object` 而导致竞争, `Async` 等待 `k8s object` 处于稳定之后, `Async` 只将 `k8s object` 对应 `queue` 中的最后一个 `event` 分发给 `consumer`

### <h3 id="1.1.2">1.1.2. VIFHandler</h3>

`VIFHandler` 将 `watch` 所有的 `pod`, 并与 `neutron` 通信为 `pod` 创建相应的 `port` 资源, 最后将 `port` 资源作为 `vif` 信息添加到 `pod annotations`.

```
# kuryr_kubernetes/controller/handlers/vif.py
class VIFHandler(k8s_base.ResourceEventHandler):
    """Controller side of VIF binding process for Kubernetes pods.

    `VIFHandler` runs on the Kuryr-Kubernetes controller and together with
    the CNI driver (that runs on 'kubelet' nodes) is responsible for providing
    networking to Kubernetes pods. `VIFHandler` relies on a set of drivers
    (which are responsible for managing Neutron resources) to define the VIF
    object and pass it to the CNI driver in form of the Kubernetes pod
    annotation.
    """

    # VIFHandler 处理 Pod event
    OBJECT_KIND = constants.K8S_OBJ_POD

    def __init__(self):
        self._drv_project = drivers.PodProjectDriver.get_instance()
        self._drv_subnets = drivers.PodSubnetsDriver.get_instance()
        self._drv_sg = drivers.PodSecurityGroupsDriver.get_instance()
        self._drv_vif = drivers.PodVIFDriver.get_instance()
        # REVISIT(ltomasbo): The VIF Handler should not be aware of the pool
        # directly. Due to the lack of a mechanism to load and set the
        # VIFHandler driver, for now it is aware of the pool driver, but this
        # will be reverted as soon as a mechanism is in place.
        self._drv_vif_pool = drivers.VIFPoolDriver.get_instance()
        self._drv_vif_pool.set_vif_driver(self._drv_vif)

    def on_present(self, pod):
        if self._is_host_network(pod) or not self._is_pending_node(pod):
            # REVISIT(ivc): consider an additional configurable check that
            # would allow skipping pods to enable heterogeneous environments
            # where certain pods/namespaces/nodes can be managed by other
            # networking solutions/CNI drivers.
            return

        vif = self._get_vif(pod)

        if not vif:
            project_id = self._drv_project.get_project(pod)
            security_groups = self._drv_sg.get_security_groups(pod, project_id)
            subnets = self._drv_subnets.get_subnets(pod, project_id)
            vif = self._drv_vif_pool.request_vif(pod, project_id, subnets,
                                                 security_groups)
            try:
                self._set_vif(pod, vif)
            except k_exc.K8sClientException as ex:
                LOG.debug("Failed to set annotation: %s", ex)
                # FIXME(ivc): improve granularity of K8sClient exceptions:
                # only resourceVersion conflict should be ignored
                self._drv_vif_pool.release_vif(pod, vif, project_id,
                                               security_groups)
        elif not vif.active:
            self._drv_vif_pool.activate_vif(pod, vif)
            self._set_vif(pod, vif)

    def on_deleted(self, pod):
        if self._is_host_network(pod):
            return

        vif = self._get_vif(pod)

        if vif:
            project_id = self._drv_project.get_project(pod)
            security_groups = self._drv_sg.get_security_groups(pod, project_id)
            self._drv_vif_pool.release_vif(pod, vif, project_id,
                                           security_groups)

    @staticmethod
    def _is_host_network(pod):
        return pod['spec'].get('hostNetwork', False)

    @staticmethod
    def _is_pending_node(pod):
        """Checks if Pod is in PENDGING status and has node assigned."""
        try:
            return (pod['spec']['nodeName'] and
                    pod['status']['phase'] == constants.K8S_POD_STATUS_PENDING)
        except KeyError:
            return False

    def _set_vif(self, pod, vif):
        # TODO(ivc): extract annotation interactions
        if vif is None:
            LOG.debug("Removing VIF annotation: %r", vif)
            annotation = None
        else:
            vif.obj_reset_changes(recursive=True)
            LOG.debug("Setting VIF annotation: %r", vif)
            annotation = jsonutils.dumps(vif.obj_to_primitive(),
                                         sort_keys=True)
        k8s = clients.get_kubernetes_client()
        k8s.annotate(pod['metadata']['selfLink'],
                     {constants.K8S_ANNOTATION_VIF: annotation},
                     resource_version=pod['metadata']['resourceVersion'])

    def _get_vif(self, pod):
        # TODO(ivc): same as '_set_vif'
        try:
            annotations = pod['metadata']['annotations']
            vif_annotation = annotations[constants.K8S_ANNOTATION_VIF]
        except KeyError:
            return None
        vif_dict = jsonutils.loads(vif_annotation)
        vif = obj_vif.vif.VIFBase.obj_from_primitive(vif_dict)
        LOG.debug("Got VIF from annotation: %r", vif)
        return vif
```

### <h3 id="1.1.3">1.1.3. LBaaSSpecHandler</h3>

`LBaaSSpecHandler` 将 `watch` 所有带有 `selector` 字段的 `k8s service`, 然后获取 `k8s service` 的相关信息并作为一个 `annotation` 添加到 `k8s service annotations` 字段和其对应的 `k8s endpoints` 字段, 后续提供给 `LoadBalancerHandler` 使用.

```
# kuryr-kubernetes/controller/handlers/lbaas.py
class LBaaSSpecHandler(k8s_base.ResourceEventHandler):
    """LBaaSSpecHandler handles K8s Service events.

    LBaaSSpecHandler handles K8s Service events and updates related Endpoints
    with LBaaSServiceSpec when necessary.
    """

    OBJECT_KIND = k_const.K8S_OBJ_SERVICE

    def __init__(self):
        self._drv_project = drv_base.ServiceProjectDriver.get_instance()
        self._drv_subnets = drv_base.ServiceSubnetsDriver.get_instance()
        self._drv_sg = drv_base.ServiceSecurityGroupsDriver.get_instance()

    def on_present(self, service):
        lbaas_spec = self._get_lbaas_spec(service)

        if self._should_ignore(service):
            LOG.debug("Skiping Kubernetes service without a selector as "
                      "Kubernetes does not create an endpoint object for it.")
            return

        if self._has_lbaas_spec_changes(service, lbaas_spec):
            lbaas_spec = self._generate_lbaas_spec(service)
            self._set_lbaas_spec(service, lbaas_spec)

    def _get_service_ip(self, service):
        spec = service['spec']
        if spec.get('type') == 'ClusterIP':
            return spec.get('clusterIP')

    def _should_ignore(self, service):
        return not(self._has_selector(service))

    def _has_selector(self, service):
        return service['spec'].get('selector')

    def _get_subnet_id(self, service, project_id, ip):
        subnets_mapping = self._drv_subnets.get_subnets(service, project_id)
        subnet_ids = {
            subnet_id
            for subnet_id, network in subnets_mapping.items()
            for subnet in network.subnets.objects
            if ip in subnet.cidr}

        if len(subnet_ids) != 1:
            raise k_exc.IntegrityError(_(
                "Found %(num)s subnets for service %(link)s IP %(ip)s") % {
                'link': service['metadata']['selfLink'],
                'ip': ip,
                'num': len(subnet_ids)})

        return subnet_ids.pop()

    def _generate_lbaas_spec(self, service):
        project_id = self._drv_project.get_project(service)
        ip = self._get_service_ip(service)
        subnet_id = self._get_subnet_id(service, project_id, ip)
        ports = self._generate_lbaas_port_specs(service)
        sg_ids = self._drv_sg.get_security_groups(service, project_id)

        return obj_lbaas.LBaaSServiceSpec(ip=ip,
                                          project_id=project_id,
                                          subnet_id=subnet_id,
                                          ports=ports,
                                          security_groups_ids=sg_ids)

    def _has_lbaas_spec_changes(self, service, lbaas_spec):
        return (self._has_ip_changes(service, lbaas_spec) or
                self._has_port_changes(service, lbaas_spec))

    def _get_service_ports(self, service):
        return [{'name': port.get('name'),
                 'protocol': port.get('protocol', 'TCP'),
                 'port': port['port']}
                for port in service['spec']['ports']]

    def _has_port_changes(self, service, lbaas_spec):
        link = service['metadata']['selfLink']

        fields = obj_lbaas.LBaaSPortSpec.fields
        svc_port_set = {tuple(port[attr] for attr in fields)
                        for port in self._get_service_ports(service)}
        spec_port_set = {tuple(getattr(port, attr) for attr in fields)
                         for port in lbaas_spec.ports}

        if svc_port_set != spec_port_set:
            LOG.debug("LBaaS spec ports %(spec_ports)s != %(svc_ports)s "
                      "for %(link)s" % {'spec_ports': spec_port_set,
                                        'svc_ports': svc_port_set,
                                        'link': link})
        return svc_port_set != spec_port_set

    def _has_ip_changes(self, service, lbaas_spec):
        link = service['metadata']['selfLink']
        svc_ip = self._get_service_ip(service)

        if not lbaas_spec:
            if svc_ip:
                LOG.debug("LBaaS spec is missing for %(link)s"
                          % {'link': link})
                return True
        elif str(lbaas_spec.ip) != svc_ip:
            LOG.debug("LBaaS spec IP %(spec_ip)s != %(svc_ip)s for %(link)s"
                      % {'spec_ip': lbaas_spec.ip,
                         'svc_ip': svc_ip,
                         'link': link})
            return True

        return False

    def _generate_lbaas_port_specs(self, service):
        return [obj_lbaas.LBaaSPortSpec(**port)
                for port in self._get_service_ports(service)]

    def _get_endpoints_link(self, service):
        svc_link = service['metadata']['selfLink']
        link_parts = svc_link.split('/')

        if link_parts[-2] != 'services':
            raise k_exc.IntegrityError(_(
                "Unsupported service link: %(link)s") % {
                'link': svc_link})
        link_parts[-2] = 'endpoints'

        return "/".join(link_parts)

    def _set_lbaas_spec(self, service, lbaas_spec):
        # TODO(ivc): extract annotation interactions
        if lbaas_spec is None:
            LOG.debug("Removing LBaaSServiceSpec annotation: %r", lbaas_spec)
            annotation = None
        else:
            lbaas_spec.obj_reset_changes(recursive=True)
            LOG.debug("Setting LBaaSServiceSpec annotation: %r", lbaas_spec)
            annotation = jsonutils.dumps(lbaas_spec.obj_to_primitive(),
                                         sort_keys=True)
        svc_link = service['metadata']['selfLink']
        ep_link = self._get_endpoints_link(service)
        k8s = clients.get_kubernetes_client()

        try:
            k8s.annotate(ep_link,
                         {k_const.K8S_ANNOTATION_LBAAS_SPEC: annotation})
        except k_exc.K8sClientException:
            # REVISIT(ivc): only raise ResourceNotReady for NotFound
            raise k_exc.ResourceNotReady(ep_link)

        k8s.annotate(svc_link,
                     {k_const.K8S_ANNOTATION_LBAAS_SPEC: annotation},
                     resource_version=service['metadata']['resourceVersion'])

    def _get_lbaas_spec(self, service):
        # TODO(ivc): same as '_set_lbaas_spec'
        try:
            annotations = service['metadata']['annotations']
            annotation = annotations[k_const.K8S_ANNOTATION_LBAAS_SPEC]
        except KeyError:
            return None
        obj_dict = jsonutils.loads(annotation)
        obj = obj_lbaas.LBaaSServiceSpec.obj_from_primitive(obj_dict)
        LOG.debug("Got LBaaSServiceSpec from annotation: %r", obj)
        return obj
```

### <h3 id="1.1.4">1.1.4. LoadBalancerHandler</h3>

`LoadBalancerHandler` 将 `watch` 所有的 `endpoints`, 并根据 `endpoints annotations` 中的 `lbaas_spec` 信息与 `neutron lbaas` 服务通信, 创建或者更新对应的 `loadbalancer`, `listeners`, `member pools`, `members` 等资源. 最后, 将 `neutron` 创建的这些资源信息作为 `lbaas_state annotations` 添加到 `endpoints` 的 `annotations` 字段.

```
# kuryr-kubernetes/controller/handlers/lbaas.py
class LoadBalancerHandler(k8s_base.ResourceEventHandler):
    """LoadBalancerHandler handles K8s Endpoints events.

    LoadBalancerHandler handles K8s Endpoints events and tracks changes in
    LBaaSServiceSpec to update Neutron LBaaS accordingly and to reflect its'
    actual state in LBaaSState.
    """

    OBJECT_KIND = k_const.K8S_OBJ_ENDPOINTS

    def __init__(self):
        self._drv_lbaas = drv_base.LBaaSDriver.get_instance()
        self._drv_pod_project = drv_base.PodProjectDriver.get_instance()
        self._drv_pod_subnets = drv_base.PodSubnetsDriver.get_instance()

    def on_present(self, endpoints):
        lbaas_spec = self._get_lbaas_spec(endpoints)
        if self._should_ignore(endpoints, lbaas_spec):
            return

        lbaas_state = self._get_lbaas_state(endpoints)
        if not lbaas_state:
            lbaas_state = obj_lbaas.LBaaSState()

        if self._sync_lbaas_members(endpoints, lbaas_state, lbaas_spec):
            # REVISIT(ivc): since _sync_lbaas_members is responsible for
            # creating all lbaas components (i.e. load balancer, listeners,
            # pools, members), it is currently possible for it to fail (due
            # to invalid Kuryr/K8s/Neutron configuration, e.g. Members' IPs
            # not belonging to configured Neutron subnet or Service IP being
            # in use by gateway or VMs) leaving some Neutron entities without
            # properly updating annotation. Some sort of failsafe mechanism is
            # required to deal with such situations (e.g. cleanup, or skip
            # failing items, or validate configuration) to prevent annotation
            # being out of sync with the actual Neutron state.
            self._set_lbaas_state(endpoints, lbaas_state)

    def on_deleted(self, endpoints):
        lbaas_state = self._get_lbaas_state(endpoints)
        if not lbaas_state:
            return
        # NOTE(ivc): deleting pool deletes its members
        lbaas_state.members = []
        self._sync_lbaas_members(endpoints, lbaas_state,
                                 obj_lbaas.LBaaSServiceSpec())

    def _should_ignore(self, endpoints, lbaas_spec):
        return not(lbaas_spec and
                   self._has_pods(endpoints) and
                   self._is_lbaas_spec_in_sync(endpoints, lbaas_spec))

    def _is_lbaas_spec_in_sync(self, endpoints, lbaas_spec):
        # REVISIT(ivc): consider other options instead of using 'name'
        ep_ports = list(set(port.get('name')
                            for subset in endpoints.get('subsets', [])
                            for port in subset.get('ports', [])))
        spec_ports = [port.name for port in lbaas_spec.ports]

        return sorted(ep_ports) == sorted(spec_ports)

    def _has_pods(self, endpoints):
        return any(True
                   for subset in endpoints.get('subsets', [])
                   for address in subset.get('addresses', [])
                   if address.get('targetRef', {}).get('kind') == 'Pod')

    def _sync_lbaas_members(self, endpoints, lbaas_state, lbaas_spec):
        changed = False

        if self._remove_unused_members(endpoints, lbaas_state, lbaas_spec):
            changed = True

        if self._sync_lbaas_pools(endpoints, lbaas_state, lbaas_spec):
            changed = True

        if self._add_new_members(endpoints, lbaas_state, lbaas_spec):
            changed = True

        return changed

    def _add_new_members(self, endpoints, lbaas_state, lbaas_spec):
        changed = False

        lsnr_by_id = {l.id: l for l in lbaas_state.listeners}
        pool_by_lsnr_port = {(lsnr_by_id[p.listener_id].protocol,
                              lsnr_by_id[p.listener_id].port): p
                             for p in lbaas_state.pools}
        pool_by_tgt_name = {p.name: pool_by_lsnr_port[p.protocol, p.port]
                            for p in lbaas_spec.ports}
        current_targets = {(str(m.ip), m.port) for m in lbaas_state.members}

        for subset in endpoints.get('subsets', []):
            subset_ports = subset.get('ports', [])
            for subset_address in subset.get('addresses', []):
                try:
                    target_ip = subset_address['ip']
                    target_ref = subset_address['targetRef']
                    if target_ref['kind'] != k_const.K8S_OBJ_POD:
                        continue
                except KeyError:
                    continue

                for subset_port in subset_ports:
                    target_port = subset_port['port']
                    if (target_ip, target_port) in current_targets:
                        continue
                    port_name = subset_port.get('name')
                    pool = pool_by_tgt_name[port_name]
                    # We use the service subnet id so that the connectivity
                    # from VIP to pods happens in layer 3 mode, i.e., routed.
                    # TODO(apuimedo): Add L2 mode
                    # TODO(apuimedo): Do not pass subnet_id at all when in
                    # L3 mode once old neutron-lbaasv2 is not supported, as
                    # octavia does not require it
                    member_subnet_id = lbaas_state.loadbalancer.subnet_id
                    member = self._drv_lbaas.ensure_member(
                        endpoints=endpoints,
                        loadbalancer=lbaas_state.loadbalancer,
                        pool=pool,
                        subnet_id=member_subnet_id,
                        ip=target_ip,
                        port=target_port,
                        target_ref=target_ref)
                    lbaas_state.members.append(member)
                    changed = True

        return changed

    def _remove_unused_members(self, endpoints, lbaas_state, lbaas_spec):
        spec_port_names = {p.name for p in lbaas_spec.ports}
        current_targets = {(a['ip'], p['port'])
                           for s in endpoints['subsets']
                           for a in s['addresses']
                           for p in s['ports']
                           if p.get('name') in spec_port_names}
        removed_ids = set()
        for member in lbaas_state.members:
            if (str(member.ip), member.port) in current_targets:
                continue
            self._drv_lbaas.release_member(endpoints,
                                           lbaas_state.loadbalancer,
                                           member)
            removed_ids.add(member.id)
        if removed_ids:
            lbaas_state.members = [m for m in lbaas_state.members
                                   if m.id not in removed_ids]
        return bool(removed_ids)

    def _sync_lbaas_pools(self, endpoints, lbaas_state, lbaas_spec):
        changed = False

        if self._remove_unused_pools(endpoints, lbaas_state, lbaas_spec):
            changed = True

        if self._sync_lbaas_listeners(endpoints, lbaas_state, lbaas_spec):
            changed = True

        if self._add_new_pools(endpoints, lbaas_state, lbaas_spec):
            changed = True

        return changed

    def _add_new_pools(self, endpoints, lbaas_state, lbaas_spec):
        changed = False

        current_listeners_ids = {pool.listener_id
                                 for pool in lbaas_state.pools}
        for listener in lbaas_state.listeners:
            if listener.id in current_listeners_ids:
                continue
            pool = self._drv_lbaas.ensure_pool(endpoints,
                                               lbaas_state.loadbalancer,
                                               listener)
            lbaas_state.pools.append(pool)
            changed = True

        return changed

    def _remove_unused_pools(self, endpoints, lbaas_state, lbaas_spec):
        current_pools = {m.pool_id for m in lbaas_state.members}
        removed_ids = set()
        for pool in lbaas_state.pools:
            if pool.id in current_pools:
                continue
            self._drv_lbaas.release_pool(endpoints,
                                         lbaas_state.loadbalancer,
                                         pool)
            removed_ids.add(pool.id)
        if removed_ids:
            lbaas_state.pools = [p for p in lbaas_state.pools
                                 if p.id not in removed_ids]
        return bool(removed_ids)

    def _sync_lbaas_listeners(self, endpoints, lbaas_state, lbaas_spec):
        changed = False

        if self._remove_unused_listeners(endpoints, lbaas_state, lbaas_spec):
            changed = True

        if self._sync_lbaas_loadbalancer(endpoints, lbaas_state, lbaas_spec):
            changed = True

        if self._add_new_listeners(endpoints, lbaas_spec, lbaas_state):
            changed = True

        return changed

    def _add_new_listeners(self, endpoints, lbaas_spec, lbaas_state):
        changed = False
        current_port_tuples = {(listener.protocol, listener.port)
                               for listener in lbaas_state.listeners}
        for port_spec in lbaas_spec.ports:
            protocol = port_spec.protocol
            port = port_spec.port
            if (protocol, port) in current_port_tuples:
                continue

            listener = self._drv_lbaas.ensure_listener(
                endpoints=endpoints,
                loadbalancer=lbaas_state.loadbalancer,
                protocol=protocol,
                port=port)
            lbaas_state.listeners.append(listener)
            changed = True
        return changed

    def _remove_unused_listeners(self, endpoints, lbaas_state, lbaas_spec):
        current_listeners = {p.listener_id for p in lbaas_state.pools}

        removed_ids = set()
        for listener in lbaas_state.listeners:
            if listener.id in current_listeners:
                continue
            self._drv_lbaas.release_listener(endpoints,
                                             lbaas_state.loadbalancer,
                                             listener)
            removed_ids.add(listener.id)
        if removed_ids:
            lbaas_state.listeners = [l for l in lbaas_state.listeners
                                     if l.id not in removed_ids]
        return bool(removed_ids)

    def _sync_lbaas_loadbalancer(self, endpoints, lbaas_state, lbaas_spec):
        changed = False
        lb = lbaas_state.loadbalancer

        if lb and lb.ip != lbaas_spec.ip:
            self._drv_lbaas.release_loadbalancer(
                endpoints=endpoints,
                loadbalancer=lb)
            lb = None
            changed = True

        if not lb and lbaas_spec.ip:
            lb = self._drv_lbaas.ensure_loadbalancer(
                endpoints=endpoints,
                project_id=lbaas_spec.project_id,
                subnet_id=lbaas_spec.subnet_id,
                ip=lbaas_spec.ip,
                security_groups_ids=lbaas_spec.security_groups_ids)
            changed = True

        lbaas_state.loadbalancer = lb
        return changed

    def _get_lbaas_spec(self, endpoints):
        # TODO(ivc): same as '_get_lbaas_state'
        try:
            annotations = endpoints['metadata']['annotations']
            annotation = annotations[k_const.K8S_ANNOTATION_LBAAS_SPEC]
        except KeyError:
            return None
        obj_dict = jsonutils.loads(annotation)
        obj = obj_lbaas.LBaaSServiceSpec.obj_from_primitive(obj_dict)
        LOG.debug("Got LBaaSServiceSpec from annotation: %r", obj)
        return obj

    def _set_lbaas_state(self, endpoints, lbaas_state):
        # TODO(ivc): extract annotation interactions
        if lbaas_state is None:
            LOG.debug("Removing LBaaSState annotation: %r", lbaas_state)
            annotation = None
        else:
            lbaas_state.obj_reset_changes(recursive=True)
            LOG.debug("Setting LBaaSState annotation: %r", lbaas_state)
            annotation = jsonutils.dumps(lbaas_state.obj_to_primitive(),
                                         sort_keys=True)
        k8s = clients.get_kubernetes_client()
        k8s.annotate(endpoints['metadata']['selfLink'],
                     {k_const.K8S_ANNOTATION_LBAAS_STATE: annotation},
                     resource_version=endpoints['metadata']['resourceVersion'])

    def _get_lbaas_state(self, endpoints):
        # TODO(ivc): same as '_set_lbaas_state'
        try:
            annotations = endpoints['metadata']['annotations']
            annotation = annotations[k_const.K8S_ANNOTATION_LBAAS_STATE]
        except KeyError:
            return None
        obj_dict = jsonutils.loads(annotation)
        obj = obj_lbaas.LBaaSState.obj_from_primitive(obj_dict)
        LOG.debug("Got LBaaSState from annotation: %r", obj)
        return obj
```


