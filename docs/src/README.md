# FastRunningMedian.jl

This Julia Package allows you to calculate a running median - fast.

## High-level API

```@docs
running_median
```

## Taperings Visualized

![Tapering Examples](docs/src/tapering%20examples.png)

## Performance Comparison

![Benchmark Comparison](docs/src/Running%20Median%20Benchmarks.png)

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
