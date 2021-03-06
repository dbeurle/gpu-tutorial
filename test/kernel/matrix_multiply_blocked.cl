//-------------------------------------------------------------
//
//  PROGRAM: Blocked Matrix Multiplication kernel
//
//  PURPOSE: Computes an element of the product matrix
//
//              C = A * B
//
//           Using the well known blocked algorithm.
//
//           To derive this algorithm, start with the naive
//           triply nested loop algorithm with a dot product
//           for each element of C.  Decompose each loop
//           into blocks of size BLOCK_SIZE.  This gives you 6
//           nested loops with three loops over blocks
//           and three loops over indices inside the blocks.
//
//           Rearrange the loops to put the 3 loops over blocks
//           at the outermost loops of the loop nest.  You'll
//           see that the three "inner" loops are just the
//           regular matrix product between blocks.
//
//           The algorithm is simple.  Keeping all the indices
//           straight is not.  We will use the following
//           conventions:
//
//             i,j,k            ... indices of full, global matrices
//             Iblk, Jblk, Kblk ... indices of matrix blocks
//             iloc, jloc, kloc ... indices inside blocks
//
//  HISTORY: Written by Tim Mattson, November 2013
//           Updated by Simon McIntosh-Smith, August 2014
//
//  LICENSE: This work is licensed under the Creative Commons
//           Attribution 4.0 International License.
//           To view a copy of this license, visit
//           http://creativecommons.org/licenses/by/4.0/
//           or send a letter to:
//              Creative Commons,
//              444 Castro Street, Suite 900,
//              Mountain View, California, 94041, USA.
//
//-------------------------------------------------------------

// It turns out that the compiler generates much better code if
// we "hardwire" this block size.  16 works well for an NVIDIA
// GPU, 32 works well for a CPU
#define BLOCK_SIZE 16

__kernel void mmul(size_t const N,
                   __global float const* A,
                   __global float const* B,
                   __global float* C,
                   __local float* Awrk,
                   __local float* Bwrk)
{
    //  This work-item will compute element C(i,j)
    size_t const i = get_global_id(0);
    size_t const j = get_global_id(1);

    // Element C(i,j) is in block C(Iblk,Jblk)
    size_t const Iblk = get_group_id(0);
    size_t const Jblk = get_group_id(1);

    // C(i,j) is element C(iloc, jloc) of block C(Iblk, Jblk)
    size_t const iloc = get_local_id(0);
    size_t const jloc = get_local_id(1);

    // The number of blocks are the same in each dimension
    size_t const Num_BLK = N / BLOCK_SIZE;

    // Setup the upper-left-corner (base address) for the A and
    // B blocks plus the increments to advance base addresses as
    // we loop over blocks
    int Abase = Jblk * N * BLOCK_SIZE;
    const int Ainc = BLOCK_SIZE;

    int Bbase = Iblk * BLOCK_SIZE;
    const int Binc = BLOCK_SIZE * N;

    float Ctmp = 0.0f;

    // C(Iblk,Jblk) = (sum over Kblk) A(Iblk,Kblk)*B(Kblk,Jblk)
    for (size_t Kblk = 0; Kblk < Num_BLK; Kblk++)
    {
        // Load A(Iblk,Kblk) and B(Kblk,Jblk) into local memory.
        // Each work-item loads a single element of the two blocks
        // which are shared with the entire work-group.
        Awrk[jloc * BLOCK_SIZE + iloc] = A[Abase + jloc * N + iloc];
        Bwrk[jloc * BLOCK_SIZE + iloc] = B[Bbase + jloc * N + iloc];

        barrier(CLK_LOCAL_MEM_FENCE);

        // Compute dot products over local blocks to find
        // the contribution to C(i,j) from this block
        for (size_t kloc = 0; kloc < BLOCK_SIZE; kloc++)
        {
            Ctmp += Awrk[jloc * BLOCK_SIZE + kloc] * Bwrk[kloc * BLOCK_SIZE + iloc];
        }

        barrier(CLK_LOCAL_MEM_FENCE);

        Abase += Ainc;
        Bbase += Binc;
    }
    // update global C matrix
    C[j * N + i] = Ctmp;
}
