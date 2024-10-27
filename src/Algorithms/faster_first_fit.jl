# FasterFirstFit node structure for the search tree and bin serach function for a custome faster first fit implementation

# FFD and BFD have potentially faster implementations using binary trees 
# Need to see if bin packing remains a bottleneck by number of problems to solve or time per problem
# see Faster First Fit for algorithm
# see AVL Tree in DataStructures.jl for implementation
# see sorted containers and serach_sorted_first function for Fatser BFD
# maybe those implementations are not suited for this purpose and there is a need for a custom tree implem (or search)
# ex : a new struture with one field being actual bins and the other being the tree used for search 

# This would require to add this tree component for searching bins inside a Bins structure to not recompute it each time
# but only updating it

# The FasterFirstFit node structure is a wrapper around :
# - index of the bin 
# - capacity of the bin
# - maximum capacity of the subtree : how to implement this property ?

# We could use an AVLTree structure from DataStructures 

# For the first fit, store a mutable key for each bin  

# By ordering nodes by the negative capacity (or by load), we can actually have an implementation of FasterBestFit 
# Keys compare with their load 
# At each step :
# - deletion of the corresponding key 
# - adding the commodity to the corresponding bin 
# - insertion of the new key

# Either way I will have to re-implement the search_node function for the AVLTree

# TODO : there is actually a need to test if this is actually more efficient 
# and not just for the worst case scenarios / large arrays of bins and commodities