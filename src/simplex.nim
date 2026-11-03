import std/[sequtils, math]

type
  SimplexResult* = object
    success*: bool
    errorMessage*: string
    objectiveCost*: float
    x*: seq[float]          # Primal variable values
    surplus*: seq[float]    # Surplus / excess for each item constraint

# Solves:
# Minimize c^T x
# Subject to: A x >= b, x >= 0
# A is (nConstraints x nVars)
# b is (nConstraints)
# c is (nVars)
# Solved via the Dual Simplex method:
# Maximize b^T y
# Subject to: A^T y <= c, y >= 0
proc solveDualSimplex*(A: seq[seq[float]], b: seq[float], c: seq[float], maxIterations = 10000): SimplexResult =
  let nConstraints = b.len
  let nVars = c.len

  if nConstraints == 0 or nVars == 0:
    return SimplexResult(success: false, errorMessage: "Empty constraint matrix or variables")

  # Dimensions of the dual tableau:
  # Rows: nVars constraints + 1 objective row
  # Cols: nConstraints (dual variables y) + nVars (slack variables w) + 1 (RHS)
  let nRows = nVars + 1
  let nCols = nConstraints + nVars + 1
  let rhsCol = nCols - 1
  let objRow = nVars

  var tableau = newSeqWith(nRows, newSeq[float](nCols))
  var basis = newSeq[int](nVars)

  # Fill dual constraints: A^T y + I w = c
  for i in 0 ..< nVars:
    for j in 0 ..< nConstraints:
      tableau[i][j] = A[j][i]
    tableau[i][nConstraints + i] = 1.0 # slack w_i
    tableau[i][rhsCol] = max(0.0, c[i]) # cost must be non-negative
    basis[i] = nConstraints + i

  # Fill objective row: maximize b^T y  =>  tableau row has -b[j]
  for j in 0 ..< nConstraints:
    tableau[objRow][j] = -b[j]

  var iter = 0
  while iter < maxIterations:
    inc iter

    # 1. Entering variable (Bland's rule: smallest index among negative reduced costs)
    var minVal = -1e-9
    var pivotCol = -1
    for j in 0 ..< nCols - 1:
      if tableau[objRow][j] < minVal:
        minVal = tableau[objRow][j]
        pivotCol = j
        # If using strict Bland's rule, we take the first negative;
        # or most negative with Bland tie-breaking.
        # Standard most negative converges faster:
    
    # If no negative coefficient in objective row, we found optimal!
    if pivotCol == -1:
      break

    # 2. Leaving variable (Ratio test: min RHS / positive entry, Bland tie-breaking)
    var minRatio = 1e20
    var pivotRow = -1
    for i in 0 ..< nVars:
      let aic = tableau[i][pivotCol]
      if aic > 1e-9:
        let ratio = tableau[i][rhsCol] / aic
        if ratio < minRatio - 1e-12:
          minRatio = ratio
          pivotRow = i

    if pivotRow == -1:
      return SimplexResult(
        success: false,
        errorMessage: "Production targets are infeasible with current recipe selection."
      )

    # 3. Pivot operation
    let pivotVal = tableau[pivotRow][pivotCol]
    for j in 0 ..< nCols:
      tableau[pivotRow][j] /= pivotVal

    for i in 0 ..< nRows:
      if i != pivotRow:
        let factor = tableau[i][pivotCol]
        if abs(factor) > 1e-13:
          for j in 0 ..< nCols:
            tableau[i][j] -= factor * tableau[pivotRow][j]

    basis[pivotRow] = pivotCol

  if iter >= maxIterations:
    return SimplexResult(
      success: false,
      errorMessage: "Solver reached maximum iteration limit."
    )

  # 4. Extract Primal Solution:
  # In the dual tableau, the reduced costs of the dual slack variables w_i (columns nConstraints ..< nConstraints + nVars)
  # in the final objective row are EXACTLY the optimal primal variables x_i!
  var x = newSeq[float](nVars)
  for i in 0 ..< nVars:
    let val = tableau[objRow][nConstraints + i]
    x[i] = if val > 1e-7: val else: 0.0

  # 5. Calculate Surplus: surplus = A x - b
  var surplus = newSeq[float](nConstraints)
  for j in 0 ..< nConstraints:
    var produced = 0.0
    for i in 0 ..< nVars:
      if x[i] > 0.0:
        produced += A[j][i] * x[i]
    let diff = produced - b[j]
    surplus[j] = if diff > 1e-6: diff else: 0.0

  return SimplexResult(
    success: true,
    objectiveCost: tableau[objRow][rhsCol],
    x: x,
    surplus: surplus
  )

