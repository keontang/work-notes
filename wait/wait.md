<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [package wait](#package-wait)
  - [Related files](#related-files)
  - [Forever](#forever)
  - [Until](#until)
  - [JitterUntil](#jitteruntil)
  - [Jitter](#jitter)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# package wait

## Related files

pkg/util/wait/wait.go

## Forever

```
// NeverStop may be passed to Until to make it never stop.
var NeverStop <-chan struct{} = make(chan struct{})

// Forever is syntactic sugar on top of Until
func Forever(f func(), period time.Duration) {
    Until(f, period, NeverStop)
}
```

Forever 周期性的执行 f 函数，永远不会停止。因为 NeverStop channel 不用来发送接收数据，只用来控制循环，如果我们不关闭 NeverStop channel，Forever 函数就会一直循环执行下去。为什么呢？下面我们看看 Until 函数。

## Until

```
// Until loops until stop channel is closed, running f every period.
// Until is syntactic sugar on top of JitterUntil with zero jitter factor
func Until(f func(), period time.Duration, stopCh <-chan struct{}) {
    JitterUntil(f, period, 0.0, stopCh)
}
```

Until 函数的功能是：周期性的执行 f 函数，除非 stopCh channel 被关闭。下面看看 JitterUntil 函数。

## JitterUntil

```
// JitterUntil loops until stop channel is closed, running f every period.
// If jitterFactor is positive, the period is jittered before every run of f.
// If jitterFactor is not positive, the period is unchanged.
// Catches any panics, and keeps going. f may not be invoked if
// stop channel is already closed. Pass NeverStop to Until if you
// don't want it stop.
func JitterUntil(f func(), period time.Duration, jitterFactor float64, stopCh <-chan struct{}) {
    /*
     * golang 中的 select 和 switch 是容易混淆的两个关键字，因为他们都带 case 语句。
     * 注意到 select 的代码形式和 switch 非常相似， 不过 select 的 case 里的操作语句只能是 IO 操作。
     * 即，golang 的 select 的功能和 select/poll/epoll 相似， 就是监听 IO 操作，当 IO 操作发生时，触发相应的动作。
     * 当 select 只有 case 语句的时候，case 不满足的话，是一直要阻塞的
     * 但是当 default 语句存在时，如果 case 语句不满足，则直接执行 default 语句而不阻塞。
     */
    select {
    case <-stopCh:
        return
    default:
    }

    /* 周期性执行 f 函数，除非 stopCh channel 已关闭 */
    for {
        func() {
            defer runtime.HandleCrash()
            f()
        }()

        jitteredPeriod := period
        /*
         * 如果 jitterFactor 为正数，则返回一个抖动周期值：period * (1 + 0.x * jitterFactor)
         * 其中 0.x 为 [0.0 1.0) 的随机值
         *
         * 如果 jitterFactor 为负数或者0.0，则周期保持不变
         *
         * 其实，引入抖动周期的目的是避免所有 clients 的周期性行为出现收敛
         * 比如，避免所有 clients 都在 0.1 秒后都需要执行各自的 f 函数
         */
        if jitterFactor > 0.0 {
            jitteredPeriod = Jitter(period, jitterFactor)
        }

        select {
        case <-stopCh:
            return
        case <-time.After(jitteredPeriod):
        }
    }
}
```

jitter 是什么呢？所谓 jitter 就是一种抖动。具体如何解释呢？其定义延迟从来源地址将要发送到目标地址，会发生不一样的延迟，这样的延迟变动是jitter让我们来看一个例子。假如你有个女友，你希望她每天晚上下班之后7点来找你，而有的时候她6:30到，有的时候是7:23，有的时候也许是下一天。这种时间上的不稳定就是jitter。如果你多观察这种时间上的不规律性，你会对 jitter 有更深一些的理解。在你观察的这段期间内，女友最早和最晚到来的时间被称为“jitter全振幅”（peak to peak jitter amplitude)。“jitter半振幅”（jitter-amplitude）就是你女友实际来的时间和7点之间的差值。女友来的时间有早有晚，jitter 半振幅也有正有负。通过计算，你可以找出 jitter 半振幅的平均值，如果你能够计算出你女友最有可能在哪个时间来，你就可以发现女友来的时间是完全无规律的（随机 jitter random jitter）还是和某些特定事情有关系（关联 jitter correlated jitter）。所谓关联 jitter 就是比如你知道你的女友周四要晚来，因为她要去看她的妈妈。如果你能彻底明白这点，你就已经是一个 correlated jitter 的专家了。

## Jitter

```
// Jitter returns a time.Duration between duration and duration + maxFactor * duration,
// to allow clients to avoid converging on periodic behavior.  If maxFactor is 0.0, a
// suggested default value will be chosen.
func Jitter(duration time.Duration, maxFactor float64) time.Duration {
    if maxFactor <= 0.0 {
        maxFactor = 1.0
    }
    /* Float64 returns, as a float64, a pseudo-random number in [0.0,1.0) from the default Source. */
    wait := duration + time.Duration(rand.Float64()*maxFactor*float64(duration))
    return wait
}
```


