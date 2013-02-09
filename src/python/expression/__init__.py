from expression import Expression, Variable, Parameter, Constant, \
    CONVEX, CONCAVE, AFFINE, NONCONVEX
from shape import Shape, SCALAR, VECTOR, MATRIX
from sign import Sign, POSITIVE, NEGATIVE, UNKNOWN
from constraint import Constraint

from utils import iscvx, isccv, isaff, \
    ispositive, isnegative, isunknown, \
    increasing, decreasing, nonmonotone, \
    isconstant
    