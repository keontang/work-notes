<!-- TOC -->

- [RNN 扩展](#rnn-扩展)
    - [双向RNN(Bidirectional RNNs)](#双向rnnbidirectional-rnns)
    - [深度双向RNN(Deep Bidirectional RNNs)](#深度双向rnndeep-bidirectional-rnns)

<!-- /TOC -->
<a id="markdown-rnn-扩展" name="rnn-扩展"></a>
# RNN 扩展

<a id="markdown-双向rnnbidirectional-rnns" name="双向rnnbidirectional-rnns"></a>
## 双向RNN(Bidirectional RNNs)

双向RNN如下图所示，它的思想是t时刻的输出不但依赖于之前的元素，而且还依赖之后的元素。比如，我们做完形填空，在句子中“挖”掉一个词，我们想预测这个词，我们不但会看前面的词，也会分析后面的词。双向RNN很简单，它就是两个RNN堆叠在一起，输出依赖两个RNN的隐状态。

![bidirectional-rnn](pics/bidirectional-RNN.png)

<a id="markdown-深度双向rnndeep-bidirectional-rnns" name="深度双向rnndeep-bidirectional-rnns"></a>
## 深度双向RNN(Deep Bidirectional RNNs)

深度双向RNN如下图所示，它和双向RNN类似，不过多加几层。当然它的表示能力更强，需要的训练数据也更多。

![stacked-bidirectional-RNN](pics/stacked-bidirectional-RNN.png)

> refer to: http://fancyerii.github.io/books/rnn-intro/

