
<a id='FastRunningMedian.jl'></a>

<a id='FastRunningMedian.jl-1'></a>

# FastRunningMedian.jl


This Julia Package allows you to calculate a running median - fast.


<a id='Installation'></a>

<a id='Installation-1'></a>

## Installation


In Julia, execute:


```julia
]add FastRunningMedian
```


<a id='High-level-API'></a>

<a id='High-level-API-1'></a>

## High-level API

<a id='FastRunningMedian.running_median' href='#FastRunningMedian.running_median'>#</a>
**`FastRunningMedian.running_median`** &mdash; *Function*.



```julia
running_median(input, window_size, tapering=:symmetric; kwargs...) -> output
```

Run a median filter of `window_size` over the input array and return the result. 

**Taperings**

The tapering decides the behaviour at the ends of the input. All taperings are mirror symmetric with respect to the middle of the input array. The available taperings are:

  * `:symmteric` or `:sym`: Ensure that the window is symmetric around each point of the output array by always growing or shrinking the window by 2. The output has the same length as the input if `window_size` is odd. If `window_size` is even, the output has one element less.
  * `:asymmetric` or `:asym`: Always adds or removes one element when calculating the next output value. Creates asymmetric windowing at the edges of the array. If the input is N long, the output is N+window_size-1 elements long.
  * `:asymmetric_truncated` or `:asym_trunc`: The same as asymmetric, but truncated at beginning and end to match the size of `:symmetric`.
  * `:none` or `:no`: No tapering towards the ends. If the input has N elements, the output is only N-window_size+1 long.

If you choose an even `window_size`, the elements of the output array lie in the middle between the input elements on a continuous underlying axis. 

**Keyword Arguments**

  * `nan=:include`: By default, NaN values in the window will turn the median NaN as well. Use `nan = :ignore` to ignore NaN values and calculate the median over the remaining values in the window. If there are only NaNs in the window, the median will be NaN regardless.
  * `output_eltype=Float64`: Element type of the output array. The output element type should allow converting from Float64 and the input element type. The exception is odd window sizes with taperings `:no` or `:sym`, in which case the output element type only has to allow converting from the input element type.

**Performance**

The underlying algorithm should scale as O(N log w) with the input size N and the window_size w. 


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/ac4104c84a42cb401206c3c18c60975fa4462391/src/FastRunningMedian.jl#L11-L52' class='documenter-source'>source</a><br>

<a id='FastRunningMedian.running_median!' href='#FastRunningMedian.running_median!'>#</a>
**`FastRunningMedian.running_median!`** &mdash; *Function*.



```julia
running_median!(mf::MedianFilter, output, input, tapering=:sym; nan=:include) -> output
```

Use `mf` to calculate the running median of `input` and write the result to `output`.

Compared to [`running_median`](README.md#FastRunningMedian.running_median), this function lets you take control of allocation for the median filter and the output vector. This is useful when you have to calculate many running medians of the same window size (see examples below).

For all details, see [`running_median`](README.md#FastRunningMedian.running_median).

**Examples**

```julia
input = [4 5 6;
         1 0 9;
         9 8 7;
         3 1 2;]
output = similar(input, (4,3))
mf = MedianFilter(42, 3) # first value does not matter
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


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/ac4104c84a42cb401206c3c18c60975fa4462391/src/FastRunningMedian.jl#L72-L106' class='documenter-source'>source</a><br>


<a id='Taperings-Visualized'></a>

<a id='Taperings-Visualized-1'></a>

## Taperings Visualized


Each data point is shown as a cross and the windows are visualized as colored boxes, the input is grey. 


![Tapering Examples](docs/resources/tapering%20examples.png)


<a id='Performance-Comparison'></a>

<a id='Performance-Comparison-1'></a>

## Performance Comparison


![Benchmark Comparison](docs/resources/Running%20Median%20Benchmarks.png)


For large window sizes, this package performs even better than calling `runmed` in R, which uses the Turlach implementation written in C. For small window sizes, the Stuetzle implementation in R still outperforms this package, but the overhead from RCall doesn't seem worth it. Development of a fast implementation for small window sizes is ongoing, see the corresponding issues for details. 


In contrast to this package, [SortFilters.jl](https://github.com/sairus7/SortFilters.jl) supports arbitrary probability levels, for example to calculate quantiles.


You can find the Notebook used to create the above graph in the `benchmark` folder. I ran it on an i7-2600K with 8 GB RAM while editing and browsing in the background. 


<a id='Stateful-API'></a>

<a id='Stateful-API-1'></a>

## Stateful API


FastRunningMedian provides a stateful API that can be used for streaming data, e. g. to reduce RAM consumption, or build your own high-level API.

<a id='FastRunningMedian.MedianFilter' href='#FastRunningMedian.MedianFilter'>#</a>
**`FastRunningMedian.MedianFilter`** &mdash; *Type*.



```julia
MedianFilter(first_val::T, window_size::Int) where T <: Real
```

Construct a stateful running median filter. 

Manipulate with [`grow!`](README.md#FastRunningMedian.grow!), [`roll!`](README.md#FastRunningMedian.roll!), [`shrink!`](README.md#FastRunningMedian.shrink!).  Query with [`median`](README.md#FastRunningMedian.median), [`length`](README.md#Base.length), [`window_size`](README.md#FastRunningMedian.window_size), [`isfull`](README.md#FastRunningMedian.isfull). 


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/ac4104c84a42cb401206c3c18c60975fa4462391/src/stateful_api.jl#L42-L49' class='documenter-source'>source</a><br>

<a id='FastRunningMedian.grow!' href='#FastRunningMedian.grow!'>#</a>
**`FastRunningMedian.grow!`** &mdash; *Function*.



```julia
grow!(mf::MedianFilter, val)
```

Grow mf with the new value `val`. 

If mf would grow beyond maximum window size, an error is thrown. In this case you probably wanted to use [`roll!`](README.md#FastRunningMedian.roll!). 

The new element is pushed onto the end of the circular buffer. 


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/ac4104c84a42cb401206c3c18c60975fa4462391/src/stateful_api.jl#L164-L173' class='documenter-source'>source</a><br>

<a id='FastRunningMedian.roll!' href='#FastRunningMedian.roll!'>#</a>
**`FastRunningMedian.roll!`** &mdash; *Function*.



```julia
roll!(mf::MedianFilter, val)
```

Roll the window over to the next position by replacing the first and oldest element in the ciruclar buffer with the new value `val`. 

Will error when `mf` is not full yet - in this case you must first [`grow!`](README.md#FastRunningMedian.grow!) mf to maximum capacity. 


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/ac4104c84a42cb401206c3c18c60975fa4462391/src/stateful_api.jl#L297-L305' class='documenter-source'>source</a><br>

<a id='FastRunningMedian.shrink!' href='#FastRunningMedian.shrink!'>#</a>
**`FastRunningMedian.shrink!`** &mdash; *Function*.



```julia
shrink!(mf::MedianFilter)
```

Shrinks `mf` by removing the first and oldest element in the circular buffer. 

Will error if mf contains only one element as a MedianFilter with zero elements would not have a median. 


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/ac4104c84a42cb401206c3c18c60975fa4462391/src/stateful_api.jl#L244-L251' class='documenter-source'>source</a><br>

<a id='FastRunningMedian.reset!' href='#FastRunningMedian.reset!'>#</a>
**`FastRunningMedian.reset!`** &mdash; *Function*.



```julia
reset!(mf::MedianFilter, first_value) -> mf
```

Reset the median filter `mf` by emptying it and initializing with `first_value`.


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/ac4104c84a42cb401206c3c18c60975fa4462391/src/stateful_api.jl#L67-L71' class='documenter-source'>source</a><br>

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


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/ac4104c84a42cb401206c3c18c60975fa4462391/src/stateful_api.jl#L96-L115' class='documenter-source'>source</a><br>

<a id='Base.length' href='#Base.length'>#</a>
**`Base.length`** &mdash; *Function*.



```julia
length(mf::MedianFilter)
```

Returns the number of elements in the stateful median filter `mf`. 

This number is equal to the length of the internal circular buffer. 


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/ac4104c84a42cb401206c3c18c60975fa4462391/src/stateful_api.jl#L139-L145' class='documenter-source'>source</a><br>

<a id='FastRunningMedian.window_size' href='#FastRunningMedian.window_size'>#</a>
**`FastRunningMedian.window_size`** &mdash; *Function*.



```julia
window_size(mf::MedianFilter)
```

Returns the window_size of the stateful median filter `mf`. 

This number is equal to the capacity of the internal circular buffer. 


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/ac4104c84a42cb401206c3c18c60975fa4462391/src/stateful_api.jl#L148-L154' class='documenter-source'>source</a><br>

<a id='FastRunningMedian.isfull' href='#FastRunningMedian.isfull'>#</a>
**`FastRunningMedian.isfull`** &mdash; *Function*.



```julia
isfull(mf::MedianFilter)
```

Returns true, when the length of the stateful median filter `mf` equals its window_size. 


<a target='_blank' href='https://github.com/Firionus/FastRunningMedian.jl/blob/ac4104c84a42cb401206c3c18c60975fa4462391/src/stateful_api.jl#L157-L161' class='documenter-source'>source</a><br>


<a id='Sources'></a>

<a id='Sources-1'></a>

## Sources


W. Hardle, W. Steiger 1995: Optimal Median Smoothing. Published in  Journal of the Royal Statistical Society, Series C (Applied Statistics), Vol. 44, No. 2 (1995), pp. 258-264. [https://doi.org/10.2307/2986349](https://doi.org/10.2307/2986349)


(I did not implement their custom double heap, but used two heaps from [DataStructures.jl](https://github.com/JuliaCollections/DataStructures.jl))


<a id='Keywords'></a>

<a id='Keywords-1'></a>

## Keywords


Running Median is also known as Rolling Median or Moving Median.

