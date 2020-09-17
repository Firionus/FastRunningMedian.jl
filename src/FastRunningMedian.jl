module FastRunningMedian

using DataStructures

export runningmedian, MedianFilter, grow!, median, length, shrink!, roll!

# Custom Orderings for DataStructures.MutableBinaryHeap
struct TupleForward <: Base.Ordering end
Base.lt(o::TupleForward, a, b) = a[1] < b[1]

struct TupleReverse <: Base.Ordering end
Base.lt(o::TupleReverse, a, b) = a[1] > b[1]

# TODO constructor and grow! with multiple values

mutable struct MedianFilter 
    low_heap::MutableBinaryHeap{Tuple{Float64, Int64}, TupleReverse} 
    high_heap::MutableBinaryHeap{Tuple{Float64, Int64}, TupleForward}
    #first tuple value is data, second tuple value is index in heap_pos (see heap_pos_offset!)

    # ordered like data in moving window would be
    # first tuple value true if in low_heap, false if in high_heap
    # second value is handle in corresponding heap
    heap_pos::CircularBuffer{Tuple{Bool,Int64}}

    heap_pos_offset::Int64 
    # heap_pos is indexed with the first element at index 1. 
    # However the indices in the heaps might go out of date whenever overwriting elements at the beginning of the circular buffer
    # This is why index_in_heap_pos = heap_pos_indices_in_heaps - heap_pos_offset
end
# TODO generic typing (Real?) instead of Float64

# Constructor
function MedianFilter(first_val::Float64, max_window_size::Int64)
    low_heap = MutableBinaryHeap{Tuple{Float64, Int64}, TupleReverse}()
    high_heap = MutableBinaryHeap{Tuple{Float64, Int64}, TupleForward}()
    heap_positions = CircularBuffer{Tuple{Bool,Int64}}(max_window_size)
    
    first_val_ind = push!(low_heap, (first_val, 1))
    
    push!(heap_positions, (true, first_val_ind))
    
    MedianFilter(low_heap, high_heap, heap_positions, 0)
end

"""
    median(mf::MedianFilter)

Determine the current median in mf. 

If the number of elements in MedianFilter is odd, the low_heap shall always be one element bigger than
the high_heap. The top element of the low_heap then is the median. 

If the number of elements in MedianFilter is even, both heaps are the same size and the
median is the mean of both top elements. 
"""
function median(mf::MedianFilter)
    if length(mf.low_heap) == length(mf.high_heap)
        # even number of elements
        # median is mean of both top elements
        return (first(mf.low_heap)[1]+first(mf.high_heap)[1])/2
    else
        # odd number of elements
        return first(mf.low_heap)[1]
    end
end

Base.length(mf::MedianFilter) = mf.heap_pos|>length

"""
    grow!(mf::MedianFilter, val)

Grow mf with the new element val. 

Returns the updated median. If mf would grow beyond
maximum window size, an error is thrown. In this case you probably wanted to use roll!. 

The new element is pushed onto the end of the circular buffer. 
"""
function grow!(mf::MedianFilter, val)
    # check that we don't grow beyond circular buffer capacity
    if length(mf.heap_pos)+1 > capacity(mf.heap_pos)
        println("current ring buffer length is ", length(mf.heap_pos))
        println("current ring buffer capacity is ", capacity(mf.heap_pos))
        error("grow! would grow circular buffer length by 1 and therefore exceed circular buffer capacity")
    end

    if length(mf.low_heap) == length(mf.high_heap)
        # even number of elements
        # low_heap needs to grow
        middle_high = first(mf.high_heap)
        if val <= middle_high[1]
            # just push! new value onto low_heap
            _push_onto_heap!(mf, val, onto_low_heap=true)
        else
            # replace middle_high in high_heap with new val and move middle_high to low_heap
            _push_displace!(mf, val, middle_high, onto_low_heap=false)
        end
    else
        # odd number of elements
        # high_heap needs to grow
        current_median = first(mf.low_heap)
        if val >= current_median[1]
            # just push! new value onto high_heap
            _push_onto_heap!(mf, val, onto_low_heap=false)
        else
            # replace current_median in low_heap with new val and move current_median to high_heap
            _push_displace!(mf, val, current_median, onto_low_heap=true)
        end
    end

    return median(mf)
end

"just push a new value onto one of the heaps and update heap_pos accordingly"
function _push_onto_heap!(mf::MedianFilter, val; onto_low_heap::Bool)
    if onto_low_heap == true
        pushed_handle = push!(mf.low_heap, (val, 0))
        push!(mf.heap_pos, (true, pushed_handle))
        mf.low_heap[pushed_handle] = (val, length(mf.heap_pos)+mf.heap_pos_offset)
    else
        pushed_handle = push!(mf.high_heap, (val, 0))
        push!(mf.heap_pos, (false, pushed_handle))
        mf.high_heap[pushed_handle] = (val, length(mf.heap_pos)+mf.heap_pos_offset)
    end
end

"push new val onto heap while displacing to_displace to the other heap"
function _push_displace!(mf::MedianFilter, val, to_displace; onto_low_heap::Bool)
    if onto_low_heap == true
        # push new val to end of circular buffer and onto low_heap where it replaces to_displace
        push!(mf.heap_pos, (true, to_displace[2]))
        update!(mf.low_heap, mf.heap_pos[to_displace[2]-mf.heap_pos_offset][2], 
            (val, length(mf.heap_pos)+mf.heap_pos_offset))
        # move to_displace onto high_heap
        pushed_handle = push!(mf.high_heap, to_displace)
        #update heap_pos
        mf.heap_pos[to_displace[2]-mf.heap_pos_offset] = (false, pushed_handle)
    else
        # push new val to end of circular buffer an onto high_heap where it replaces to_displace
        push!(mf.heap_pos, (false, to_displace[2]))
        update!(mf.high_heap, mf.heap_pos[to_displace[2]-mf.heap_pos_offset][2], 
            (val, length(mf.heap_pos)+mf.heap_pos_offset))
        # move to_displace onto low_heap
        pushed_handle = push!(mf.low_heap, to_displace)
        # update heap_pos
        mf.heap_pos[to_displace[2]-mf.heap_pos_offset] = (true, pushed_handle)
    end
end

"""
    shrink!(mf::MedianFilter)

Shrinks mf by removing the first and oldest element in the circular buffer. 

Returns the updated median. Will error if mf contains only one element as a MedianFilter with zero elements
would not have a median. 
"""
function shrink!(mf::MedianFilter)
    if length(mf.heap_pos) <= 1
        error("MedianFilter of length 1 cannot be shrunk further because it would not have a median anymore")
    end

    # TODO write something here and update everything below

end

function shrinkby2!(mf::MedianFilter)
    #println("entering shrinkby2! with ", mf)

    # remove the two values at the start of the circular buffer while shrinking it and the heap
    flag = 1 # how much bigger low_heap is in comparison to high_heap
    for k in 1:2
        to_remove = popfirst!(mf.heap_pos)
        #println("trying to remove ", to_remove)
        mf.heap_pos_offset += 1
        if to_remove[1] == true
            # element to remove is in low_heap
            delete!(mf.low_heap, to_remove[2])
            flag -= 1
        else
            # element to remove is in high_heap
            delete!(mf.high_heap, to_remove[2])
            flag += 1
        end
    #println("after removing (another) one we have ", mf)

    # sanity check
    for k in 1:length(mf.heap_pos)
        current_heap, current_heap_ind = mf.heap_pos[k]
        if current_heap == true
            a = mf.low_heap[current_heap_ind][2] - mf.heap_pos_offset
            #println(k, " ?= ", a)
            @assert k == a
        else
            a = mf.high_heap[current_heap_ind][2] - mf.heap_pos_offset
            #println(k, " ?= ", a)
            @assert k == a
        end
    end

    #println("which passed its health check")

    end

    equalize_heap_size!(mf, flag)

    #println("after equalizing we have ", mf)
    return median(mf)
end

function roll!(mf::MedianFilter, val::Float64)
    
    # sanity check
    if length(mf.heap_pos) != capacity(mf.heap_pos)
        error("When rolling, maximum capacity of ring buffer must be met")
    end
    # TODO remove this restriction - may want to run 53 window over 6 data points. It is totally well defined. 
    
    
    if val <= median(mf)
        val_goes_into_low_heap = true
    else
        val_goes_into_low_heap = false
    end
    
    to_replace = mf.heap_pos[1]
    
    if to_replace[1] == true
        removed_from_low_heap = true
    else
        removed_from_low_heap = false
    end
    
    mf.heap_pos_offset += 1
    
    if removed_from_low_heap == val_goes_into_low_heap
        # no equalization necessary
        if val_goes_into_low_heap           
            update!(mf.low_heap, to_replace[2], (val, capacity(mf.heap_pos)+mf.heap_pos_offset))
            push!(mf.heap_pos, to_replace)
        else
            #val goes into high heap
            update!(mf.high_heap, to_replace[2], (val, capacity(mf.heap_pos)+mf.heap_pos_offset))
            push!(mf.heap_pos, to_replace)
        end
    else 
        # need to equalize
        if val_goes_into_low_heap
            med, med_ind = top_with_handle(mf.low_heap)
            update!(mf.low_heap, med_ind, (val, capacity(mf.heap_pos)+mf.heap_pos_offset))
            push!(mf.heap_pos, (true, med_ind))
            update!(mf.high_heap, to_replace[2], med)
            mf.heap_pos[med[2]-mf.heap_pos_offset] = (false, to_replace[2])
        else        
            # val goes into high heap, but removed from low heap
 
            #check if val is new median
            if val>=median(mf) && val<=first(mf.high_heap)[1]
                update!(mf.low_heap, to_replace[2], (val, capacity(mf.heap_pos)+mf.heap_pos_offset))
                push!(mf.heap_pos, to_replace)
            else #val is not new median
                abovemed, abovemed_ind = top_with_handle(mf.high_heap)
                update!(mf.high_heap, abovemed_ind, (val, capacity(mf.heap_pos)+mf.heap_pos_offset))
                push!(mf.heap_pos, (false, abovemed_ind))
                update!(mf.low_heap, to_replace[2], abovemed)
                mf.heap_pos[abovemed[2]-mf.heap_pos_offset] = (true, to_replace[2])
            end
            
        end
    end
    return median(mf)
end


# TODO remove restrictions on input and window size where reasonably well defined behaviour can be accomplished
# TODO add asymmetric tapering of window towards end
"""
    runningmedian(input::Array{Float64, 1}, max_window_size=53)

Compute the running median over input with maximum window size of `max_window_size`. 

`max_window_size` must be an odd number. 

The window is shrinked towards the start and end such that it is symmetric around the center value. 
Therefore, the first and last values of the returned array are the same as in input. 

The implementation uses an efficient double heap algorithm that scales roughly O(N log(W)) where 
N is the size of `input` and W is the window size. 
"""
function runningmedian(input::Array{Float64, 1}, max_window_size=53)
    if iseven(max_window_size) || max_window_size <= 1
        error("max_window_size must be odd number of 3 or bigger")
    elseif length(input) < 3
       error("input must be at least 3 elements long, otherwise function would return identity")
    else # max_window_size is odd
        if length(input)|>isodd
            max_possible_window_size = length(input)
        else
            max_possible_window_size = length(input)-1
        end
    end

    # assign no value bigger than max_possible_window_size to not break circular buffer behaviour
    if max_possible_window_size < max_window_size
        max_window_size = max_possible_window_size
    end

    # allocate output array
    output = similar(input)
    
    # maximum one-sided offset
    max_offset = round((max_window_size-1)/2, Base.Rounding.RoundNearestTiesAway)|>Int
    
    prev_offset = 0
    mymf = MedianFilter(input[1], max_window_size)
    output[1] = median(mymf)
    
    for j in 2:length(input)
        current_offset = min(max_offset, j-1, length(input)-j)
        #println(prev_offset, " followed by ", current_offset)
        if current_offset == prev_offset + 1
            #grow
            output[j] = growby2!(mymf, input[j+current_offset-1:j+current_offset])
        elseif current_offset == prev_offset - 1
            #shrink
            output[j] = shrinkby2!(mymf)
        elseif current_offset == prev_offset
            #roll
            output[j] = roll!(mymf, input[j+current_offset])
        else
            println("max_offset is ", max_offset)
            error("current_offset and prev_offset do not differ by -2, 0 or 2.")
        end
        prev_offset = current_offset
        #println(mymf)

        # sanity check
        for k in 1:length(mymf.heap_pos)
            current_heap, current_heap_ind = mymf.heap_pos[k]
            if current_heap == true
                a = mymf.low_heap[current_heap_ind][2] - mymf.heap_pos_offset
                #println(k, " ?= ", a)
                @assert k == a
            else
                a = mymf.high_heap[current_heap_ind][2] - mymf.heap_pos_offset
                #println(k, " ?= ", a)
                @assert k == a
            end
        end
    end
    output
end

end # module
