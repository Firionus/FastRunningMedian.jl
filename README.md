
<a id='FastRunningMedian.jl'></a>

<a id='FastRunningMedian.jl-1'></a>

# FastRunningMedian.jl


This Julia Package allows you to calculate a running median - fast.


<a id='Getting-Started'></a>

<a id='Getting-Started-1'></a>

## Getting Started


In Julia, install with:


```julia
]add FastRunningMedian
```


Example Usage:


```julia-repl
julia> using FastRunningMedian

julia> running_median([1,9,2,3,-9,1], 3)
6-element Vector{Float64}:
 1.0
 2.0
 3.0
 2.0
 1.0
 1.0
```


<a id='High-level-API'></a>

<a id='High-level-API-1'></a>

## High-level API

<a id='FastRunningMedian.running_median' href='#FastRunningMedian.running_median'>#</a>
**`FastRunningMedian.running_median`** &mdash; *Function*.



```julia
running_median(input, window_length, tapering=:symmetric; kwargs...) -> output
```

Run a median filter of `window_length` over the input array and return the result. 

If the input array is multidimensional, the median will be run only over the first dimension, i.e. over all columns indepedently.

**Taperings**

The tapering decides the behaviour at the ends of the input. The available taperings are:

  * `:symmteric` or `:sym`: Ensure that the window is symmetric around each point of the output array by always growing or shrinking the window by 2. The output has the same length as the input if `window_length` is odd. If `window_length` is even, the output has one element less.
  * `:asymmetric` or `:asym`: Always adds or removes one element when calculating the next output value. Creates asymmetric windowing at the edges of the array. If the input is N long, the output is N+window_length-1 elements long.
  * `:asymmetric_truncated` or `:asym_trunc`: The same as asymmetric, but truncated at beginning and end to match the length of `:symmetric`.
  * `:none` or `:no`: No tapering towards the ends. If the input has N elements, the output is only N-window_length+1 long. Equivalent to "roll" from RollingFunctions.
  * `:beginning_only` or `:start`: At the beginning, always grow the window by one but do not taper the end. This is equivalent to asymmetric but truncated at the end such that the output length matches the input length. Equivalent to "run" from RollingFunctions.

If you choose an even `window_length`, the elements of the output array lie in the middle between the input elements on a continuous underlying axis. 

With the exception of `:beginning_only`, all taperings are mirror symmetric with respect to the middle of the input array.

**Keyword Arguments**

  * `nan=:include`: By default, NaN values in the window will turn the median NaN as well. Use `nan = :ignore` to ignore NaN values and calculate the median over the remaining values in the window. If there are only NaNs in the window, the median will be NaN regardless.
  * `output_eltype=Float64`: Element type of the output array. The output element type should allow converting from Float64 and the input element type. The exception is odd window lengths with taperings `:no` or `:sym`, in which case the output element type only has to allow converting from the input element type.

**Performance**

The underlying algorithm should scale as O(N log w) with the input length N and the window_length w. 


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/442679b03e6203344231e2341a133b82fea0e1c0/src/FastRunningMedian.jl#L10-L62' class='documenter-source'>source</a><br>


<a id='Taperings-Visualized'></a>

<a id='Taperings-Visualized-1'></a>

## Taperings Visualized


Each data point is shown as a cross and the windows are visualized as colored boxes, the input is grey. 


<p align="center">     <img src="docs/resources/tapering%20examples.png" alt="Tapering Examples" width="90%"> </p>


<a id='Performance-Comparison'></a>

<a id='Performance-Comparison-1'></a>

## Performance Comparison


![Benchmark Comparison](docs/resources/Running%20Median%20Benchmarks.png)


For large window lengths, this package performs even better than calling `runmed` in R, which uses the Turlach implementation written in C. For small window lengths, the Stuetzle implementation in R still outperforms this package, but the overhead from RCall doesn't seem worth it. Development of a fast implementation for small window lengths is ongoing, see the corresponding issues for details. 


In contrast to this package, [SortFilters.jl](https://github.com/sairus7/SortFilters.jl) supports arbitrary probability levels, for example to calculate quantiles.


You can find the Notebook used to create the above graph in the `benchmark` folder. I ran it on an i7-2600K with 8 GB RAM while editing and browsing in the background. 


<a id='Mid-level-API'></a>

<a id='Mid-level-API-1'></a>

## Mid-level API


You can take control of allocating the output vector and median filter with a lower-level API. This is useful when you have to calculate many running medians of the same window length. 

<a id='FastRunningMedian.running_median!' href='#FastRunningMedian.running_median!'>#</a>
**`FastRunningMedian.running_median!`** &mdash; *Function*.



```julia
running_median!(mf::MedianFilter, output, input, tapering=:sym; nan=:include) -> output
```

Use `mf` to calculate the running median of `input` and write the result to `output`.

For all details, see [`running_median`](README.md#FastRunningMedian.running_median).

**Examples**

```julia
input = [4 5 6;
         1 0 9;
         9 8 7;
         3 1 2;]
output = similar(input, (4,3))
mf = MedianFilter(eltype(input), 3)
for j in axes(input, 2) # run median over each column
    # re-use mf in every iteration
    running_median!(mf, @view(output[:,j]), input[:,j])
end
output

# output
4×3 Matrix{Int64}:
 4  5  6
 4  5  7
 3  1  7
 3  1  2
```


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/442679b03e6203344231e2341a133b82fea0e1c0/src/FastRunningMedian.jl#L81-L110' class='documenter-source'>source</a><br>


<a id='Stateful-API'></a>

<a id='Stateful-API-1'></a>

## Stateful API


The stateful API can be used for streaming data, e. g. to reduce RAM consumption, or building your own high-level API.

<a id='FastRunningMedian.MedianFilter' href='#FastRunningMedian.MedianFilter'>#</a>
**`FastRunningMedian.MedianFilter`** &mdash; *Type*.



```julia
MedianFilter([T=Float64,] window_length) where T <: Real
```

Construct a stateful running median filter, taking values of type `T`. 

Manipulate with [`grow!`](README.md#FastRunningMedian.grow!), [`roll!`](README.md#FastRunningMedian.roll!), [`shrink!`](README.md#FastRunningMedian.shrink!), [`reset!`](README.md#FastRunningMedian.reset!).  Query with [`median`](README.md#FastRunningMedian.median), [`length`](README.md#Base.length), [`window_length`](README.md#FastRunningMedian.window_length), [`isfull`](README.md#FastRunningMedian.isfull). 

**Examples**

```julia-repl
julia> mf = MedianFilter(Int64, 2)
MedianFilter{Int64}(MutableBinaryHeap(), MutableBinaryHeap(), Tuple{FastRunningMedian.ValueLocation, Int64}[], 0, 0)

julia> grow!(mf, 1); median(mf) # window: [1]
1

julia> grow!(mf, 2); median(mf) # window: [1,2]
1.5

julia> roll!(mf, 3); median(mf) # window: [2,3]
2.5

julia> shrink!(mf); median(mf) # window: [3]
3
```


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/442679b03e6203344231e2341a133b82fea0e1c0/src/stateful_api.jl#L50-L75' class='documenter-source'>source</a><br>

<a id='FastRunningMedian.grow!' href='#FastRunningMedian.grow!'>#</a>
**`FastRunningMedian.grow!`** &mdash; *Function*.



```julia
grow!(mf::MedianFilter, val) -> mf
```

Grow mf with the new value `val`. 

If mf would grow beyond maximum window length, an error is thrown. In this case you probably wanted to use [`roll!`](README.md#FastRunningMedian.roll!). 

The new element is pushed onto the end of the circular buffer. 


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/442679b03e6203344231e2341a133b82fea0e1c0/src/stateful_api.jl#L156-L165' class='documenter-source'>source</a><br>

<a id='FastRunningMedian.roll!' href='#FastRunningMedian.roll!'>#</a>
**`FastRunningMedian.roll!`** &mdash; *Function*.



```julia
roll!(mf::MedianFilter, val) -> mf
```

Roll the window over to the next position by replacing the first and oldest element in the ciruclar buffer with the new value `val`. 


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/442679b03e6203344231e2341a133b82fea0e1c0/src/stateful_api.jl#L289-L294' class='documenter-source'>source</a><br>

<a id='FastRunningMedian.shrink!' href='#FastRunningMedian.shrink!'>#</a>
**`FastRunningMedian.shrink!`** &mdash; *Function*.



```julia
shrink!(mf::MedianFilter) -> mf
```

Shrinks `mf` by removing the first and oldest element in the circular buffer. 

Will error if mf contains only one element as a MedianFilter with zero elements would not have a median. 


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/442679b03e6203344231e2341a133b82fea0e1c0/src/stateful_api.jl#L236-L243' class='documenter-source'>source</a><br>

<a id='FastRunningMedian.reset!' href='#FastRunningMedian.reset!'>#</a>
**`FastRunningMedian.reset!`** &mdash; *Function*.



```julia
reset!(mf::MedianFilter) -> mf
```

Reset the median filter `mf` by emptying it.


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/442679b03e6203344231e2341a133b82fea0e1c0/src/stateful_api.jl#L375-L379' class='documenter-source'>source</a><br>

<a id='FastRunningMedian.median' href='#FastRunningMedian.median'>#</a>
**`FastRunningMedian.median`** &mdash; *Function*.



```julia
median(mf::MedianFilter; nan=:include)
```

Determine the current median in `mf`. 

**NaN Handling**

By default, any NaN value in the filter will turn the result NaN.

Use the keyword argument `nan = :ignore` to ignore NaN values and calculate the median  over the remaining values. If there are only NaNs, the median will be NaN regardless. 

**Implementation**

If the number of elements in MedianFilter is odd, the low_heap is always one element bigger than the high_heap. The top element of the low_heap then is the median. 

If the number of elements in MedianFilter is even, both heaps are the same size and the median is the mean of both top elements. 


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/442679b03e6203344231e2341a133b82fea0e1c0/src/stateful_api.jl#L88-L107' class='documenter-source'>source</a><br>

<a id='Base.length' href='#Base.length'>#</a>
**`Base.length`** &mdash; *Function*.



```julia
length(mf::MedianFilter)
```

Returns the number of elements in the stateful median filter `mf`. 

This number is equal to the length of the internal circular buffer. 


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/442679b03e6203344231e2341a133b82fea0e1c0/src/stateful_api.jl#L131-L137' class='documenter-source'>source</a><br>

<a id='FastRunningMedian.window_length' href='#FastRunningMedian.window_length'>#</a>
**`FastRunningMedian.window_length`** &mdash; *Function*.



```julia
window_length(mf::MedianFilter)
```

Returns the window_length of the stateful median filter `mf`. 

This number is equal to the capacity of the internal circular buffer. 


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/442679b03e6203344231e2341a133b82fea0e1c0/src/stateful_api.jl#L140-L146' class='documenter-source'>source</a><br>

<a id='FastRunningMedian.isfull' href='#FastRunningMedian.isfull'>#</a>
**`FastRunningMedian.isfull`** &mdash; *Function*.



```julia
isfull(mf::MedianFilter)
```

Returns true when the length of the stateful median filter `mf` equals its window length. 


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/442679b03e6203344231e2341a133b82fea0e1c0/src/stateful_api.jl#L149-L153' class='documenter-source'>source</a><br>


<a id='Sources'></a>

<a id='Sources-1'></a>

## Sources


W. Hardle, W. Steiger 1995: Optimal Median Smoothing. Published in  Journal of the Royal Statistical Society, Series C (Applied Statistics), Vol. 44, No. 2 (1995), pp. 258-264. [https://doi.org/10.2307/2986349](https://doi.org/10.2307/2986349)


(I did not implement their custom double heap, but used two heaps from [DataStructures.jl](https://github.com/JuliaCollections/DataStructures.jl))


<a id='Keywords'></a>

<a id='Keywords-1'></a>

## Keywords


Running Median is also known as Rolling Median or Moving Median.

