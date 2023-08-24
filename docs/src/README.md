# FastRunningMedian.jl

This Julia Package allows you to calculate a running median - fast.

## Getting Started

In Julia, install with:

```julia
]add FastRunningMedian
```

Example Usage:

```jldoctest
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

## High-level API

```@docs
running_median
```

## Taperings Visualized

Each data point is shown as a cross and the windows are visualized as colored boxes, the input is grey. 

<p align="center">
    <img src="docs/resources/tapering%20examples.png" alt="Tapering Examples" width="70%">
</p>

## Performance Comparison

![Benchmark Comparison](docs/resources/Running%20Median%20Benchmarks.png)

For large window lengths, this package performs even better than calling `runmed` in R, which uses the Turlach implementation written in C. For small window lengths, the Stuetzle implementation in R still outperforms this package, but the overhead from RCall doesn't seem worth it. Development of a fast implementation for small window lengths is ongoing, see the corresponding issues for details. 

In contrast to this package, [SortFilters.jl](https://github.com/sairus7/SortFilters.jl) supports arbitrary probability levels, for example to calculate quantiles.

You can find the Notebook used to create the above graph in the `benchmark` folder. I ran it on an i7-2600K with 8 GB RAM while editing and browsing in the background. 

## Mid-level API

You can take control of allocating the output vector and median filter with a lower-level API. This is useful when you
have to calculate many running medians of the same window length. 

```@docs
running_median!
```

## Stateful API

The stateful API can be used for streaming data, e. g. to reduce RAM consumption, or building your own high-level API.

```@docs
MedianFilter
grow!
roll!
shrink!
reset!
median
length
window_length
isfull
```

## Sources

W. Hardle, W. Steiger 1995: Optimal Median Smoothing. Published in  Journal of the Royal Statistical Society, Series C (Applied Statistics), Vol. 44, No. 2 (1995), pp. 258-264. <https://doi.org/10.2307/2986349>

(I did not implement their custom double heap, but used two heaps from [DataStructures.jl](https://github.com/JuliaCollections/DataStructures.jl))

## Keywords

Running Median is also known as Rolling Median or Moving Median.
