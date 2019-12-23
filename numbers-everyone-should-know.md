# Numbers Everyone Should Know

| device | average access time |
| :-----| :---- |
| L1 cache reference 读取CPU的一级缓存 | 0.5 ns |
| Branch mispredict (转移、分支预测) | 5 ns |
| L2 cache reference 读取CPU的二级缓存 | 7 ns |
| Mutex lock/unlock 互斥锁/解锁 | 100 ns |
| Main memory reference 读取内存数据 | 100 ns |
| Compress 1K bytes with Zippy 1K 字节压缩 | 10 us |
| Send 2K bytes over 1 Gbps network 在 1Gbps 的网络上发送 2K 字节 | 20 us |
| Read 1 MB sequentially from memory 从内存顺序读取 1MB | 250 us |
| Round trip within same datacenter 从一个数据中心往返一次，ping 一下 | 500 us |
| Disk seek 磁盘搜索 | 10 ms |
| Read 1 MB sequentially from network 从网络上顺序读取 1M 的数据 | 10 ms |
| Read 1 MB sequentially from disk 从磁盘里面读出 1MB | 30 ms |
| Send packet CA->Netherlands->CA 一个包的一次远程访问 | 150 ms |
