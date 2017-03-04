import math
import numpy as np

def generateTerrain(width, height, smoothness):
    size = smallestPowerOfTwoAfter(max(width, height))
    squareTerrain = generateSquareTerrain(size, smoothness)
    return squareTerrain[0:height,0:width]

def smallestPowerOfTwoAfter(n):
    ret = 1
    while ret < n:
        ret *= 2
    return ret

def generateSquareTerrain(size, smoothness):
    # throw error if size is not a power of two.
    if size & (size - 1) != 0:
        raise "Expected terrain size to be a power of 2"

    # generate a square matrix
    mat = np.zeros((size+1, size+1))

    # iterate on the matrix using the square-diamond algorithm
    iterate(mat, smoothness)

    return mat

def iterate(matrix, smoothness):
    # the count of iterations applied so far
    counter = 0
    # the total number of iterations to apply is log_2^(size of matrix)
    numIteration = math.log2(matrix.shape[0] - 1)
    while counter < numIteration:
        counter += 1
        diamond(matrix, counter, smoothness)
        square(matrix, counter, smoothness)

def diamond(matrix, depth, smoothness):
    len = matrix.shape[0]
    terrainSize = len - 1
    numSegs = 1 << (depth - 1)
    span = terrainSize // numSegs
    half = span // 2

    # enumerate sub-squares 
    # for each sub-square, the height of the center is caculated
    # by averaging the height of its four vertices plus a random offset.
    for x in range(0, terrainSize, span):
        for y in range(0, terrainSize, span):
            #  (x, y)
            #    \
            #     a---b---c
            #     |   |   |
            #     d---e---f
            #     |   |   |
            #     g---h---i
            # 
            #     \___ ___/
            #         V
            #       span 
            # 

            # heights of vertices
            heights = matrix[(y,y,y+span,y+span),(x,x+span,x,x+span)]

            # average height
            avg = np.average(heights)

            # random offset
            offset = getH(smoothness, depth)

            # set center height
            matrix[y + half, x + half] = avg + offset


def square(matrix, depth, smoothness):
    len = matrix.shape[0]
    terrainSize = len - 1
    numSegs = 1 << (depth - 1)
    span = terrainSize // numSegs
    half = span // 2

    # enumerate sub-dimaonds 
    for x in range(0, terrainSize, span):
        for y in range(0, terrainSize, span):
            # for each sub-square, the height of the center is caculated
            # by averaging the height of its four vertices plus a random offset.
            # for example, 
            #       h = avg(g, c, i, m) + random;
            #       f = avg(a, g, k, i) + random;
            #       j = f;
            #
            #  (x, y)
            #    \
            #     a---b---c---d---e
            #     | \ | / | \ | / |
            #     f---g---h---i---j
            #     | / | \ | / | \ |
            #     k---l---m---n---o
            #     | \ | / | \ | / |
            #     p---q---r---s---t
            #     | / | \ | / | \ |
            #     u---v---w---x---y
            # 
            #     \___ ___/
            #         V
            #       span 
            # 
             va = [x, y]
             vb = [x + half, y]
             vc = [x + span, y]
             vf = [x, y + half]
             vg = [x + half, y + half]
             vh = [x + span, y + half]
             vk = [x, y + span]
             vl = [x + half, y + span]
             vm = [x + span, y + span]
        
             # right of h
             vhr = [x + half * 3, y + half]
             if vhr[0] > terrainSize:
                 vhr[0] = half

             # left of f
             vfl = [x - half, y + half]
             if vfl[0] < 0:
                 vfl[0] = terrainSize - half

             # under l
             vlu = [x + half, y + half * 3]
             if vlu[1] > terrainSize:
                 vlu[1] = half

             # above b
             vba = [x + half, y - half]
             if vba[1] < 0:
                 vba[1] = terrainSize - half

             squareHelper(matrix, depth, smoothness, (va, vg, vk, vfl), vf)
             squareHelper(matrix, depth, smoothness, (va, vba, vc, vg), vb)
             squareHelper(matrix, depth, smoothness, (vc, vhr, vm, vg), vh)
             squareHelper(matrix, depth, smoothness, (vk, vg, vm, vlu), vl)

    # set the elevations of the rightmost and bottom vertices to 
    # equal the leftmost and topmost ones'.
    for y in range(0, terrainSize, span):
        matrix[y,terrainSize] = matrix[y,0]
    for x in range(0, terrainSize, span):
        matrix[terrainSize,x] = matrix[0,x]

def squareHelper(matrix, depth, smoothness, vs, t):
    height = 0.0
    for v in vs:
        height += matrix[v[1],v[0]]
    avg = height/len(vs)
    offset = getH(smoothness, depth)
    matrix[t[1],t[0]] = avg + offset
    
def getH(smoothness, depth):
    sign = 1.0 if np.random.random() > 0.5 else -1.0
    scale = math.pow(2, -smoothness*depth)
    return sign * np.random.random() * scale
