using DataStructures

export MedianFilter, grow!, shrink!, roll!, reset!, isfull, median, length, window_size

# Custom Orderings for DataStructures.MutableBinaryHeap
struct TupleForward <: Base.Ordering end
Base.lt(o::TupleForward, a, b) = a[1] < b[1]

struct TupleReverse <: Base.Ordering end
Base.lt(o::TupleReverse, a, b) = a[1] > b[1]

@enum ValueLocation::Int8 lo hi nan

# Main struct in this package - provides state for stateful median calculation
mutable struct MedianFilter{T}
    low_heap::MutableBinaryHeap{Tuple{T,Int},TupleReverse}
    high_heap::MutableBinaryHeap{Tuple{T,Int},TupleForward}
    # first tuple value is data, second tuple value is index in heap_pos (see heap_pos_offset!)

    # ordered like data in moving window would be
    # first tuple value indicates whether values is in low heap, high heap or an Nan (not in heaps)
    # second value is handle in corresponding heap; NaN's are 0
    heap_pos::CircularBuffer{Tuple{ValueLocation,Int}}

    heap_pos_offset::Int
    # heap_pos is indexed with the first element at index 1. 
    # However the indices in the heaps might go out of date whenever overwriting elements at the beginning of the circular buffer
    # This is why index_in_heap_pos = heap_pos_indices_in_heaps - heap_pos_offset

    nans::Int # number of NaN values in heap_pos

    # Inner constructor to enforce T <: Real
    function MedianFilter(low_heap::MutableBinaryHeap{Tuple{T,Int},TupleReverse},
        high_heap::MutableBinaryHeap{Tuple{T,Int},TupleForward},
        heap_pos::CircularBuffer{Tuple{ValueLocation,Int}},
        heap_pos_offset::Int,
        nans::Int) where {T<:Real}
        return new{T}(low_heap, high_heap, heap_pos, heap_pos_offset, nans)
    end
end

"""
    MedianFilter(first_val::T, window_size::Int) where T <: Real

Construct a stateful running median filter. 

Manipulate with [`grow!`](@ref), [`roll!`](@ref), [`shrink!`](@ref). 
Query with [`median`](@ref), [`length`](@ref), [`window_size`](@ref), [`isfull`](@ref). 
"""
function MedianFilter(first_val::T, window_size::Int) where {T<:Real}
    high_heap = MutableBinaryHeap{Tuple{T,Int},TupleForward}()
    high_heap_max_size = window_size ÷ 2
    sizehint!(high_heap, high_heap_max_size)

    low_heap = MutableBinaryHeap{Tuple{T,Int},TupleReverse}()
    sizehint!(low_heap, window_size - high_heap_max_size)

    heap_positions = CircularBuffer{Tuple{ValueLocation,Int}}(window_size)

    mf = MedianFilter(low_heap, high_heap, heap_positions, 0, 0)
    reset!(mf, first_val)
end

"""
    reset!(mf::MedianFilter, first_value)

Reset the median filter `mf` by emptying it and initializing with `first_value`.
"""
function reset!(mf::MedianFilter, first_value)
    _empty_heap!(mf.high_heap)
    _empty_heap!(mf.low_heap)
    empty!(mf.heap_pos)

    if first_value |> isnan
        push!(mf.heap_pos, (nan, 0))
        mf.nans = 1
    else
        first_value_ind = push!(mf.low_heap, (first_value, 1))
        push!(mf.heap_pos, (lo, first_value_ind))
        mf.nans = 0
    end

    mf.heap_pos_offset = 0

    mf
end

# TODO this might move into DataStructures.jl in the future
# track https://github.com/JuliaCollections/DataStructures.jl/issues/866
function _empty_heap!(heap)
    while !isempty(heap)
        pop!(heap)
    end
    return heap
end

"""
    median(mf::MedianFilter; nan=:include)

Determine the current median in `mf`. 

## NaN Handling

By default, any NaN value in the filter will turn the result NaN.

Use the keyword argument `nan = :ignore` to ignore NaN values and calculate the median 
over the remaining values. If there are only NaNs, the median will be NaN regardless. 

## Implementation

If the number of elements in MedianFilter is odd, the low\\_heap is always one element bigger than
the high\\_heap. The top element of the low\\_heap then is the median. 

If the number of elements in MedianFilter is even, both heaps are the same size and the
median is the mean of both top elements. 
"""
function median(mf::MedianFilter; nan=:include)
    if !(nan in (:include, :ignore))
        throw(ArgumentError("nan must be :include or :ignore"))
    end

    if mf.nans > 0 && nan == :include
        return NaN
    end

    if mf.low_heap |> isempty
        return NaN
    end

    if length(mf.low_heap) == length(mf.high_heap)
        # even number of elements
        # median is mean of both top elements
        return first(mf.low_heap)[1] / 2 + first(mf.high_heap)[1] / 2
    else
        # odd number of elements
        return first(mf.low_heap)[1]
    end
end

"""
    length(mf::MedianFilter)

Returns the number of elements in the stateful median filter `mf`. 

This number is equal to the length of the internal circular buffer. 
"""
Base.length(mf::MedianFilter) = mf.heap_pos |> length

"""
    window_size(mf::MedianFilter)

Returns the window_size of the stateful median filter `mf`. 

This number is equal to the capacity of the internal circular buffer. 
"""
window_size(mf::MedianFilter) = mf.heap_pos |> DataStructures.capacity

"""
    isfull(mf::MedianFilter)

Returns true, when the length of the stateful median filter `mf` equals its window\\_size. 
"""
isfull(mf::MedianFilter) = mf.heap_pos |> DataStructures.isfull

"""
    grow!(mf::MedianFilter, val)

Grow mf with the new value `val`. 

If mf would grow beyond maximum window size, an error is thrown. In this case
you probably wanted to use [`roll!`](@ref). 

The new element is pushed onto the end of the circular buffer. 
"""
function grow!(mf::MedianFilter, val)
    # check that we don't grow beyond circular buffer capacity
    if length(mf) + 1 > window_size(mf)
        error("grow! would grow circular buffer length by 1 and therefore exceed circular buffer capacity")
    end

    _grow_unchecked!(mf, val)
end

function _grow_unchecked!(mf::MedianFilter, val)
    if val |> isnan
        mf.nans += 1
        push!(mf.heap_pos, (nan, 0))
        return
    end

    if length(mf.low_heap) == 0
        # just push! new value onto low_heap
        pushed_handle = push!(mf.low_heap, (val, 0))
        push!(mf.heap_pos, (lo, pushed_handle))
        mf.low_heap[pushed_handle] = (val, length(mf.heap_pos) + mf.heap_pos_offset)
        return
    end

    if length(mf.low_heap) == length(mf.high_heap)
        # even number of elements
        # low_heap needs to grow
        middle_high = first(mf.high_heap)
        if val <= middle_high[1]
            # just push! new value onto low_heap
            pushed_handle = push!(mf.low_heap, (val, 0))
            push!(mf.heap_pos, (lo, pushed_handle))
            mf.low_heap[pushed_handle] = (val, length(mf.heap_pos) + mf.heap_pos_offset)
        else
            # replace middle_high in high_heap with new val and move middle_high to low_heap

            # push new val to end of circular buffer and onto high_heap where it replaces to_displace
            push!(mf.heap_pos, mf.heap_pos[middle_high[2]-mf.heap_pos_offset])
            update!(mf.high_heap, mf.heap_pos[middle_high[2]-mf.heap_pos_offset][2],
                (val, length(mf.heap_pos) + mf.heap_pos_offset))
            # move middle_high onto low_heap
            pushed_handle = push!(mf.low_heap, middle_high)
            # update heap_pos
            mf.heap_pos[middle_high[2]-mf.heap_pos_offset] = (lo, pushed_handle)
        end
    else
        # odd number of elements
        # high_heap needs to grow
        current_median = first(mf.low_heap)
        if val >= current_median[1]
            # just push! new value onto high_heap
            pushed_handle = push!(mf.high_heap, (val, 0))
            push!(mf.heap_pos, (hi, pushed_handle))
            mf.high_heap[pushed_handle] = (val, length(mf.heap_pos) + mf.heap_pos_offset)
        else
            # replace current_median in low_heap with new val and move current_median to high_heap

            # push new val to end of circular buffer and onto low_heap where it replaces current_median
            push!(mf.heap_pos, mf.heap_pos[current_median[2]-mf.heap_pos_offset])
            update!(mf.low_heap, mf.heap_pos[current_median[2]-mf.heap_pos_offset][2],
                (val, length(mf.heap_pos) + mf.heap_pos_offset))
            # move current_median onto high_heap
            pushed_handle = push!(mf.high_heap, current_median)
            # update heap_pos
            mf.heap_pos[current_median[2]-mf.heap_pos_offset] = (hi, pushed_handle)
        end
    end
end

"""
    shrink!(mf::MedianFilter)

Shrinks `mf` by removing the first and oldest element in the circular buffer. 

Will error if mf contains only one element as a MedianFilter with zero elements
would not have a median. 
"""
function shrink!(mf::MedianFilter)
    if length(mf.heap_pos) <= 1
        error("MedianFilter of length 1 cannot be shrunk further because it would not have a median anymore")
    end

    _shrink_unchecked!(mf)
end

function _shrink_unchecked!(mf::MedianFilter)
    to_remove = popfirst!(mf.heap_pos)
    mf.heap_pos_offset += 1

    if to_remove[1] == nan
        mf.nans -= 1
        return
    end

    if length(mf.low_heap) == length(mf.high_heap)
        # even number of elements
        # high_heap needs to get smaller
        if to_remove[1] == lo
            # element-to-remove is in low_heap
            medium_high = pop!(mf.high_heap)
            update!(mf.low_heap, to_remove[2], medium_high)
            mf.heap_pos[medium_high[2]-mf.heap_pos_offset] = to_remove
        else
            # element-to-remove is in high_heap
            delete!(mf.high_heap, to_remove[2])
        end
    else
        # odd number of elements
        # low_heap needs to get smaller
        if to_remove[1] == lo
            # element-to-remove is in low_heap
            delete!(mf.low_heap, to_remove[2])
        else
            # element-to-remove is in high_heap
            current_median = pop!(mf.low_heap)
            update!(mf.high_heap, to_remove[2], current_median)
            mf.heap_pos[current_median[2]-mf.heap_pos_offset] = to_remove
        end
    end
    return
end

"""
    roll!(mf::MedianFilter, val)

Roll the window over to the next position by replacing the first and oldest
element in the ciruclar buffer with the new value `val`. 

Will error when `mf` is not full yet - in this case you must first
[`grow!`](@ref) mf to maximum capacity. 
"""
function roll!(mf::MedianFilter, val)
    if !isfull(mf)
        error("when rolling, maximum capacity of ring buffer must be met")
    end

    to_replace = mf.heap_pos[1]

    if to_replace[1] == nan || val |> isnan
        # might not be performance optimal
        _shrink_unchecked!(mf)
        _grow_unchecked!(mf, val)
        return
    end

    new_heap_element = (val, window_size(mf) + mf.heap_pos_offset + 1)

    if mf.high_heap |> isempty
        update!(mf.low_heap, to_replace[2], new_heap_element)
        push!(mf.heap_pos, to_replace)
        mf.heap_pos_offset += 1
        return
    end

    if val < first(mf.low_heap)[1]
        # val should go into low_heap
        if to_replace[1] == lo
            # hole in low_heap
            update!(mf.low_heap, to_replace[2], new_heap_element)
            push!(mf.heap_pos, to_replace)
            mf.heap_pos_offset += 1
        elseif to_replace[1] == hi
            # hole in high_heap
            low_top, low_top_ind = top_with_handle(mf.low_heap)
            # shift low_top into hole in high_heap
            update!(mf.high_heap, to_replace[2], low_top)
            # don't forget to update indices in heap_pos
            mf.heap_pos[low_top[2]-mf.heap_pos_offset] = (hi, to_replace[2])
            # put new val where low_top is
            update!(mf.low_heap, low_top_ind, new_heap_element)
            # perform circular push on circular buffer
            push!(mf.heap_pos, (lo, low_top_ind))
            mf.heap_pos_offset += 1
        end
    elseif val > first(mf.high_heap)[1]
        # val should go into high_heap
        if to_replace[1] == lo
            # hole in low_heap
            high_top, high_top_ind = top_with_handle(mf.high_heap)
            # shift high_top into hole in low_heap
            update!(mf.low_heap, to_replace[2], high_top)
            # dont't forget to udpate indices in heap_pos
            mf.heap_pos[high_top[2]-mf.heap_pos_offset] = (lo, to_replace[2])
            # put new val where high_top is
            update!(mf.high_heap, high_top_ind, new_heap_element)
            # perform circular push on circular buffer
            push!(mf.heap_pos, (hi, high_top_ind))
            mf.heap_pos_offset += 1
        elseif to_replace[1] == hi
            # hole in high_heap
            update!(mf.high_heap, to_replace[2], new_heap_element)
            push!(mf.heap_pos, to_replace)
            mf.heap_pos_offset += 1
        end
    else
        # low_top <= val <= high_top
        # put whereever hole is
        if to_replace[1] == lo
            # hole in low_heap
            update!(mf.low_heap, to_replace[2], new_heap_element)
            push!(mf.heap_pos, to_replace)
            mf.heap_pos_offset += 1
        elseif to_replace[1] == hi
            # hole in high_heap
            update!(mf.high_heap, to_replace[2], new_heap_element)
            push!(mf.heap_pos, to_replace)
            mf.heap_pos_offset += 1
        end
    end
    return
end