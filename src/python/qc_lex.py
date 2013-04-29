"""
The design of this module borrows heavily from the PLY manual and the
pycparser library.
"""
# import re
# import expression as e
import operator
from qc_ply import lex
from qc_atoms import atoms
# from atoms import macros, abs_, norm, sum_


class QCLexer:
    def __init__(self): # does nothing yet
        pass
        
    def build(self, **kwargs):
        """ Builds the lexer from the specification. Must be
            called after the lexer object is created. 
            
            This method exists separately, because the PLY
            manual warns against calling lex.lex inside
            __init__
        """
        self.lexer = lex.lex(module=self, **kwargs)
        
    # Test it output
    def test(self,data):
        self.lexer.input(data)
        while True:
             tok = self.lexer.token()
             if not tok: break
             print tok
    
    # reserved keywords in the language
    reserved = dict([
        ('variable', 'VARIABLE'),
        ('parameter', 'PARAMETER'),
        ('dimension', 'DIMENSION'),
        #'expression'  : 'EXPRESSION',
        ('variables', 'VARIABLES'),
        ('parameters', 'PARAMETERS'),
        ('dimensions', 'DIMENSIONS'),
        #'expressions' : 'EXPRESSIONS',
        ('positive', 'SIGN'),
        ('negative', 'SIGN'),
        ('nonnegative', 'SIGN'),
        ('nonpositive', 'SIGN'),
        ('minimize', 'SENSE'),
        ('maximize', 'SENSE'),
        ('find', 'SENSE'),
        ('subject', 'SUBJ'),
        ('to', 'TO'),
        # builtin functions in the language
        ('norm', 'NORM'),
        ('norm2', 'NORM'),
        ('abs', 'ABS'),
        ('sum', 'SUM'),
        #'norms' : 'NORM',
    ] + zip(atoms.keys(),['ATOM']*len(atoms.keys())))

    tokens = [
        'INTEGER','CONSTANT', 'PLUS', 'MINUS', 'TIMES', 'DIVIDE', 'EQ', 'LEQ', 'GEQ',
        'COMMA', 'SEMI', 'TRANSPOSE', 'LBRACE', 'RBRACE', 'LPAREN', 'RPAREN',
        'ID', 'COMMENT', 'NL'
    ] + list(set(reserved.values()))

    t_PLUS      = r'\+'
    t_MINUS     = r'\-'
    t_TIMES     = r'\*'
    t_DIVIDE    = r'/'
    # t_ASSIGN    = r'='
    t_EQ        = r'=='
    t_LEQ       = r'<='
    t_GEQ       = r'>='
    t_COMMA     = r','
    t_SEMI      = r';'
    t_TRANSPOSE = r'\''
    t_LBRACE    = r'\['
    t_RBRACE    = r'\]'
    t_LPAREN    = r'\('
    t_RPAREN    = r'\)'

    # for parsing integers
    def t_INTEGER(self,t):
        r'\d+'
        t.value = int(t.value)
        return t
        
    # for parsing constant floats
    def t_CONSTANT(self,t):
        r'\d+\.\d*'
        t.value = float(t.value)
        return t
    


    # for identifiers
    def t_ID(self,t):
        r'[a-zA-Z_][a-zA-Z_0-9]*'
        t.type = self.reserved.get(t.value, 'ID')
        return t

    def t_COMMENT(self,t):
        r'\#.*'
        pass
        # comment token

    # newline rule
    def t_NL(self,t):
        r'\n+'
        t.lexer.lineno += len(t.value)
        return t

    # things to ignore (spaces and tabs)
    t_ignore = ' \t'

    # error handling
    def t_error(self,t):
        print "QC_LEX: Illegal character '%s'" % t.value[0]
        t.lexer.skip(1)
        