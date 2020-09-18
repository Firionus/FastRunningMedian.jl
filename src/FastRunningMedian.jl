module FastRunningMedian

using DataStructures

export runningmedian

# Custom Orderings for DataStructures.MutableBinaryHeap
struct TupleForward <: Base.Ordering end
Base.lt(o::TupleForward, a, b) = a[1] < b[1]

struct TupleReverse <: Base.Ordering end
Base.lt(o::TupleReverse, a, b) = a[1] > b[1]

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
# TODO generic typing instead of Float64

# Constructor
function MedianFilter(first_val::Float64, max_window_size::Int64)
    low_heap = MutableBinaryHeap{Tuple{Float64, Int64}, TupleReverse}()
    high_heap = MutableBinaryHeap{Tuple{Float64, Int64}, TupleForward}()
    heap_positions = CircularBuffer{Tuple{Bool,Int64}}(max_window_size)
    
    first_val_ind = push!(low_heap, (first_val, 1))
    
    push!(heap_positions, (true, first_val_ind))
    
    MedianFilter(low_heap, high_heap, heap_positions, 0)
end

#Base.first(h::MutableBinaryHeap) = h.nodes[1].value
# This should be exported by DataStructures, but somehow isn't...
# TODO Check why this isn't exported by DataStructures

function median(mf::MedianFilter)
    # The low_heap is always kept one element bigger than the high_heap
    # The top element of the low_heap then is the current median
    first(mf.low_heap)[1]
end

# TODO replace all usages of this function with smarter usage of push!, update!, remove!, pop!, etc. 
# where we already know what values to push over to the other heap
function equalize_heap_size!(mf, flag)
    if flag == 1
        #all good
    elseif flag == 3
        # low_heap too big
        # move highest value in low_heap up to high_heap
        popped_val = pop!(mf.low_heap)
        pushed_to = push!(mf.high_heap, popped_val)
        mf.heap_pos[popped_val[2]-mf.heap_pos_offset] = (false, pushed_to)
    elseif flag == -1
        # high_heap too big
        # move lowest value of high_heap down
        popped_val = pop!(mf.high_heap)
        pushed_to = push!(mf.low_heap, popped_val)
        mf.heap_pos[popped_val[2]-mf.heap_pos_offset] = (true, pushed_to)
    else
        errors("flag does not have a valid value")
    end
end

# grow by 2, these are assumed to correlate to the next two values from data and are just pushed onto heap_positions
function growby2!(mf::MedianFilter, vals) 
    
    #must not grow beyond max_window_size!!!!!! Otherwise not valid!!!!
    if length(mf.heap_pos)+2 > capacity(mf.heap_pos)
        #println("current ring buffer length is ", length(mf.heap_pos))
        #println("current ring buffer capacity is ", capacity(mf.heap_pos))
        error("groby2! would grow beyond ring buffer capacity and result in invalid state")
    end
    
    
    flag = 1 # how much bigger low_heap is in comparison to high_heap
    for k in 1:2 #both vals
        if vals[k] > first(mf.low_heap)[1]
            #push onto high_heap
            pushed_ind = push!(mf.high_heap, (vals[k], 0))
            push!(mf.heap_pos, (false, pushed_ind))
            update!(mf.high_heap, pushed_ind, (vals[k], length(mf.heap_pos)+mf.heap_pos_offset))
            flag -= 1
        else 
            #push onto low_heap
            pushed_ind = push!(mf.low_heap, (vals[k], 0))
            push!(mf.heap_pos, (true, pushed_ind))
            update!(mf.low_heap, pushed_ind, (vals[k], length(mf.heap_pos)+mf.heap_pos_offset))
            flag += 1
        end
    end
    
    equalize_heap_size!(mf, flag)
    
    return median(mf)
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
        #=
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
        =#
    end
    output
end

end # module
