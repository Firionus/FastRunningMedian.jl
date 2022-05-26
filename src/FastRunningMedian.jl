module FastRunningMedian

using Base.Iterators: isdone
using DataStructures

# Stateful API
export MedianFilter, grow!, shrink!, roll!, isfull, median, length, window_size
# Stateless API
export running_median

# Custom Orderings for DataStructures.MutableBinaryHeap
struct TupleForward <: Base.Ordering end
Base.lt(o::TupleForward, a, b) = a[1] < b[1]

struct TupleReverse <: Base.Ordering end
Base.lt(o::TupleReverse, a, b) = a[1] > b[1]

# Main struct in this package - provides state for stateful median calculation
mutable struct MedianFilter{T}
    low_heap::MutableBinaryHeap{Tuple{T,Int},TupleReverse} 
    high_heap::MutableBinaryHeap{Tuple{T,Int},TupleForward}
    # first tuple value is data, second tuple value is index in heap_pos (see heap_pos_offset!)

    # ordered like data in moving window would be
    # first tuple value true if in low_heap, false if in high_heap
    # second value is handle in corresponding heap
    heap_pos::CircularBuffer{Tuple{Bool,Int}}

    heap_pos_offset::Int
    # heap_pos is indexed with the first element at index 1. 
    # However the indices in the heaps might go out of date whenever overwriting elements at the beginning of the circular buffer
    # This is why index_in_heap_pos = heap_pos_indices_in_heaps - heap_pos_offset

    # Inner constructor to enforce T <: Real
    function MedianFilter(low_heap::MutableBinaryHeap{Tuple{T,Int},TupleReverse}, 
        high_heap::MutableBinaryHeap{Tuple{T,Int},TupleForward}, 
        heap_pos::CircularBuffer{Tuple{Bool,Int}}, 
        heap_pos_offset::Int) where T <: Real
        return new{T}(low_heap, high_heap, heap_pos, heap_pos_offset)
    end
end

"""
    MedianFilter(first_val::T, window_size::Int) where T <: Real

Construct a stateful running median filter. 

Manipulate with [`grow!`](@ref), [`roll!`](@ref), [`shrink!`](@ref). 
Query with [`median`](@ref), [`length`](@ref), [`window_size`](@ref), [`isfull`](@ref). 
"""
function MedianFilter(first_val::T, window_size::Int) where T <: Real
    low_heap = MutableBinaryHeap{Tuple{T,Int},TupleReverse}()
    high_heap = MutableBinaryHeap{Tuple{T,Int},TupleForward}()
    heap_positions = CircularBuffer{Tuple{Bool,Int}}(window_size)
    
    first_val_ind = push!(low_heap, (first_val, 1))
    
    push!(heap_positions, (true, first_val_ind))
    
    MedianFilter(low_heap, high_heap, heap_positions, 0)
end

"""
    median(mf::MedianFilter)

Determine the current median in `mf`. 

## Implementation

If the number of elements in MedianFilter is odd, the low\\_heap is always one element bigger than
the high\\_heap. The top element of the low\\_heap then is the median. 

If the number of elements in MedianFilter is even, both heaps are the same size and the
median is the mean of both top elements. 
"""
function median(mf::MedianFilter)
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

    if length(mf.low_heap) == length(mf.high_heap)
        # even number of elements
        # low_heap needs to grow
        middle_high = first(mf.high_heap)
        if val <= middle_high[1]
            # just push! new value onto low_heap
            pushed_handle = push!(mf.low_heap, (val, 0))
            push!(mf.heap_pos, (true, pushed_handle))
            mf.low_heap[pushed_handle] = (val, length(mf.heap_pos) + mf.heap_pos_offset)
        else
            # replace middle_high in high_heap with new val and move middle_high to low_heap

            # push new val to end of circular buffer an onto high_heap where it replaces to_displace
            push!(mf.heap_pos, mf.heap_pos[middle_high[2]])
            update!(mf.high_heap, mf.heap_pos[middle_high[2] - mf.heap_pos_offset][2], 
                (val, length(mf.heap_pos) + mf.heap_pos_offset))
            # move middle_high onto low_heap
            pushed_handle = push!(mf.low_heap, middle_high)
            # update heap_pos
            mf.heap_pos[middle_high[2] - mf.heap_pos_offset] = (true, pushed_handle)
        end
    else
        # odd number of elements
        # high_heap needs to grow
        current_median = first(mf.low_heap)
        if val >= current_median[1]
            # just push! new value onto high_heap
            pushed_handle = push!(mf.high_heap, (val, 0))
            push!(mf.heap_pos, (false, pushed_handle))
            mf.high_heap[pushed_handle] = (val, length(mf.heap_pos) + mf.heap_pos_offset)
        else
            # replace current_median in low_heap with new val and move current_median to high_heap

            # push new val to end of circular buffer and onto low_heap where it replaces current_median
            push!(mf.heap_pos, mf.heap_pos[current_median[2]])
            update!(mf.low_heap, mf.heap_pos[current_median[2] - mf.heap_pos_offset][2], 
                (val, length(mf.heap_pos) + mf.heap_pos_offset))
            # move current_median onto high_heap
            pushed_handle = push!(mf.high_heap, current_median)
            # update heap_pos
            mf.heap_pos[current_median[2] - mf.heap_pos_offset] = (false, pushed_handle)
        end
    end
    return
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

    to_remove = popfirst!(mf.heap_pos)
    mf.heap_pos_offset += 1

    if length(mf.low_heap) == length(mf.high_heap)
        # even number of elements
        # high_heap needs to get smaller
        if to_remove[1] == true
            # element-to-remove is in low_heap
            medium_high = pop!(mf.high_heap)
            update!(mf.low_heap, to_remove[2], medium_high)
            mf.heap_pos[medium_high[2] - mf.heap_pos_offset] = to_remove
        else
            # element-to-remove is in high_heap
            delete!(mf.high_heap, to_remove[2])
        end
    else
        # odd number of elements
        # low_heap needs to get smaller
        if to_remove[1] == true
            # element-to-remove is in low_heap
            delete!(mf.low_heap, to_remove[2])
        else
            # element-to-remove is in high_heap
            current_median = pop!(mf.low_heap)
            update!(mf.high_heap, to_remove[2], current_median)
            mf.heap_pos[current_median[2] - mf.heap_pos_offset] = to_remove
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
        error("When rolling, maximum capacity of ring buffer must be met")
    end

    to_replace = mf.heap_pos[1]
    new_heap_element = (val, window_size(mf) + mf.heap_pos_offset + 1)

    if window_size(mf) == 1
        update!(mf.low_heap, to_replace[2], new_heap_element)
        push!(mf.heap_pos, to_replace)
        mf.heap_pos_offset += 1
    else
        if val < first(mf.low_heap)[1]
            # val should go into low_heap
            if to_replace[1] == true
                # hole in low_heap
                update!(mf.low_heap, to_replace[2], new_heap_element)
                push!(mf.heap_pos, to_replace)
                mf.heap_pos_offset += 1
            else
                # hole in high_heap
                low_top, low_top_ind = top_with_handle(mf.low_heap)
                # shift low_top into hole in high_heap
                update!(mf.high_heap, to_replace[2], low_top)
                # don't forget to update indices in heap_pos
                mf.heap_pos[low_top[2] - mf.heap_pos_offset] = (false, to_replace[2])
                # put new val where low_top is
                update!(mf.low_heap, low_top_ind, new_heap_element)
                # perform circular push on circular buffer
                push!(mf.heap_pos, (true, low_top_ind))
                mf.heap_pos_offset += 1
            end
        elseif val > first(mf.high_heap)[1]
            # val should go into high_heap
            if to_replace[1] == true
                # hole in low_heap
                high_top, high_top_ind = top_with_handle(mf.high_heap)
                # shift high_top into hole in low_heap
                update!(mf.low_heap, to_replace[2], high_top)
                # dont't forget to udpate indices in heap_pos
                mf.heap_pos[high_top[2] - mf.heap_pos_offset] = (true, to_replace[2])
                # put new val where high_top is
                update!(mf.high_heap, high_top_ind, new_heap_element)
                # perform circular push on circular buffer
                push!(mf.heap_pos, (false, high_top_ind))
                mf.heap_pos_offset += 1
            else
                # hole in high_heap
                update!(mf.high_heap, to_replace[2], new_heap_element)
                push!(mf.heap_pos, to_replace)
                mf.heap_pos_offset += 1
            end
        else
            # low_top <= val <= high_top
            # put whereever hole is
            if to_replace[1] == true
                # hole in low_heap
                update!(mf.low_heap, to_replace[2], new_heap_element)
                push!(mf.heap_pos, to_replace)
                mf.heap_pos_offset += 1
            else
                # hole in high_heap
                update!(mf.high_heap, to_replace[2], new_heap_element)
                push!(mf.heap_pos, to_replace)
                mf.heap_pos_offset += 1
            end
        end
    end
    return
end

"""
    running_median(input, window_size, tapering=:symmetric)

Run a median filter of `window_size` over the input array and return the result. 

## Taperings

The tapering decides the behaviour at the ends of the input. All taperings are mirror symmetric with respect to the middle of the input array. The available taperings are:
- `:symmteric` or `:sym`: Ensure that the window is symmetric around each point of the output array by always growing or shrinking the window by 2. The output has the same length as the input if `window_size` is odd. If `window_size` is even, the output has one element less. 
- `:asymmetric` or `:asym`: Always adds or removes one element when calculating the next output value. Creates asymmetric windowing at the edges of the array. If the input is N long, the output is N+window_size-1 elements long. 
- `:asymmetric_truncated` or `:asym_trunc`: The same as asymmetric, but truncated at beginning and end to match the size of `:symmetric`. 
- `:none` or `:no`: No tapering towards the ends. If the input has N elements, the output is only N-window_size+1 long. 

If you choose an even `window_size`, the elements of the output array lie in the middle between the input elements on a continuous underlying axis. 

## Performance

The underlying algorithm should scale as O(N log w) with the input size N and the window_size w. 
"""
function running_median(input::AbstractVector{T}, window_size::Integer, tapering=:symmetric) where T <: Real
    if length(input) == 0
        error("input array must be non-empty")
    end

    if window_size < 1
        error("window_size must be 1 or bigger")
    end

    if tapering == :symmetric || tapering == :sym
        symmetric_running_median(input, window_size)
    elseif tapering == :asymmetric || tapering == :asym
        asymmetric_running_median(input, window_size)
    elseif tapering == :asymmetric_truncated || tapering == :asym_trunc
        asymmetric_truncated_running_median(input, window_size)
    elseif tapering == :none || tapering == :no
        untapered_running_median(input, window_size)
    else
        error("Invalid tapering. Must be one of [:sym, :asym, :asym_trunc, :no]")
    end
end

function symmetric_running_median(input::AbstractVector{T}, window_size::Integer) where T <: Real
    N = length(input)

    # calculate maximum possible window size
    if N |> isodd
        max_possible_window_size = N
    else
        max_possible_window_size = N - 1
    end
    # assign no value bigger than max_possible_window_size to not break circular buffer behaviour
    if max_possible_window_size < window_size
        window_size = max_possible_window_size
    end

    # allocate output
    if window_size |> iseven
        N_out = N - 1
    else
        N_out = N
    end
    output = Array{Float64,1}(undef, N_out)

    # input iterator
    it = Iterators.Stateful(input)

    # construct MedianFilter
    mf = MedianFilter(popfirst!(it), window_size)

    # if even, start with two elements in mf at index 1.5
    if window_size |> iseven
        grow!(mf, popfirst!(it))
    end

    # first median
    j = 1
    output[j] = median(mf)
    j += 1

    # grow phase
    while !isfull(mf)
        grow!(mf, popfirst!(it))
        grow!(mf, popfirst!(it))
        output[j] = median(mf)
        j += 1
    end

    # roll phase
    while !isdone(it)
        roll!(mf, popfirst!(it))
        output[j] = median(mf)
        j += 1
    end

    # shrink phase
    while j <= N_out
        shrink!(mf)
        shrink!(mf)
        output[j] = median(mf)
        j += 1
    end

    return output
end

function asymmetric_running_median(input::AbstractVector{T}, window_size::Integer) where T <: Real
    N = length(input)

    # calculate maximum possible window size
    max_possible_window_size = N
    # assign no value bigger than max_possible_window_size to not break circular buffer behaviour
    if max_possible_window_size < window_size
        window_size = max_possible_window_size
    end
    
    # allocate output
    N_out = N + window_size - 1
    output = Array{Float64,1}(undef, N_out)

    # input iterator
    it = Iterators.Stateful(input)

    # construct MedianFilter
    mf = MedianFilter(popfirst!(it), window_size)

    # first median
    j = 1
    output[j] = median(mf)
    j += 1

    # grow phase
    while !isfull(mf)
        grow!(mf, popfirst!(it))
        output[j] = median(mf)
        j += 1
    end

    # roll phase
    while !isdone(it)
        roll!(mf, popfirst!(it))
        output[j] = median(mf)
        j += 1
    end

    # shrink phase
    while j <= N_out
        shrink!(mf)
        output[j] = median(mf)
        j += 1
    end

    return output
end

function asymmetric_truncated_running_median(input::AbstractVector{T}, window_size::Integer) where T <: Real
    N = length(input)

    # calculate maximum possible window size
    max_possible_window_size = N
    # assign no value bigger than max_possible_window_size to not break circular buffer behaviour
    if max_possible_window_size < window_size
        window_size = max_possible_window_size
    end

    # allocate output
    if window_size |> iseven
        N_out = N - 1
    else
        N_out = N
    end
    output = Array{Float64,1}(undef, N_out)

    # input iterator
    it = Iterators.Stateful(input)

    # construct MedianFilter
    mf = MedianFilter(popfirst!(it), window_size)

    # pre-output grow phase
    while length(mf) <= window_size / 2
        grow!(mf, popfirst!(it))
    end

    # first median
    j = 1
    output[j] = median(mf)
    j += 1

    # grow phase
    while !isfull(mf)
        grow!(mf, popfirst!(it))
        output[j] = median(mf)
        j += 1
    end

    # roll phase
    while !isdone(it)
        roll!(mf, popfirst!(it))
        output[j] = median(mf)
        j += 1
    end

    # shrink phase
    while j <= N_out
        shrink!(mf)
        output[j] = median(mf)
        j += 1
    end

    return output
end

function untapered_running_median(input::AbstractVector{T}, window_size::Integer) where T <: Real
    N = length(input)

    # calculate maximum possible window size
    max_possible_window_size = N
    # assign no value bigger than max_possible_window_size to not break circular buffer behaviour
    if max_possible_window_size < window_size
        window_size = max_possible_window_size
    end

    # allocate output
    N_out = N - window_size + 1
    output = Array{Float64,1}(undef, N_out)

    # input iterator
    it = Iterators.Stateful(input)

    # construct MedianFilter
    mf = MedianFilter(popfirst!(it), window_size)

    # grow phase - no output yet
    while !isfull(mf)
        grow!(mf, popfirst!(it))
    end
    
    # first median
    j = 1
    output[j] = median(mf)
    j += 1

    # roll phase
    while !isdone(it)
        roll!(mf, popfirst!(it))
        output[j] = median(mf)
        j += 1
    end

    return output
end

end # module
