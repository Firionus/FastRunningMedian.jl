# FastRunningMedian.jl

This Julia Package allows you to calculate a running median - fast.

## Installation

In Julia, execute:

```julia
]add FastRunningMedian
```

## High-level API

```@docs
running_median
```

## Taperings Visualized

Each data point is shown as a cross and the windows are visualized as colored boxes, the input is grey. 

![Tapering Examples](docs/src/tapering%20examples.png)

## Performance Comparison

![Benchmark Comparison](docs/src/Running%20Median%20Benchmarks.png)

For large window sizes, this package performs even better than calling `runmed` in R, which uses the Turlach implementation written in C. For small window sizes, the Stuetzle implementation in R still outperforms this package, but the overhead from RCall doesn't seem worth it. If you want to add a fast implementation for small window sizes to this package, feel free to put in a PR or open an issue with any questions you might have.

In contrast to this package, [SortFilters.jl](https://github.com/sairus7/SortFilters.jl) supports arbitrary probability levels, for example to calculate quantiles.

You can find the Notebook used to create the above graph in the `benchmark` folder. I ran it on an i7-2600K with 8 GB RAM while editing and browsing in the background. 

## Stateful API

FastRunningMedian provides a stateful API that can be used for streaming data, e. g. to reduce RAM consumption, or build your own high-level API.

```@docs
MedianFilter
grow!
roll!
shrink!
median
length
window_size
isfull
```

## Sources

W. Hardle, W. Steiger 1995: Optimal Median Smoothing. Published in  Journal of the Royal Statistical Society, Series C (Applied Statistics), Vol. 44, No. 2 (1995), pp. 258-264. <https://doi.org/10.2307/2986349>

(I did not implement their custom double heap, but used two heaps from [DataStructures.jl](https://github.com/JuliaCollections/DataStructures.jl))

## Keywords

Running Median is also known as Rolling Median or Moving Median.
