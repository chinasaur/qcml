module Parser.CVX (cvxProb, CVXParser, lexer, 
  module Text.ParserCombinators.Parsec,
  module Text.ParserCombinators.Parsec.Token) where
  import qualified Expression.Expression as E
  import qualified Data.Map as M
  import Rewriter.Atoms
  
  import Data.Maybe
  
  import Text.ParserCombinators.Parsec.Token
  import Text.ParserCombinators.Parsec.Language
  import Text.ParserCombinators.Parsec
  import Text.ParserCombinators.Parsec.Expr
  
  -- to be removed later
  import Rewriter.ECOS
  
  type CVXState = M.Map String E.CVXSymbol
  type CVXParser a = GenParser Char CVXState a
  symbolTable = M.empty :: CVXState

  lexer :: TokenParser CVXState
  lexer = makeTokenParser (haskellDef {
      reservedNames = ["minimize", "maximize", "subject to", "parameter", "variable", "nonnegative", "nonpositive"],
      reservedOpNames = ["*", "+", "-", "==", "<=", ">="] ++ (M.keys ecosAtoms)
    })
    
  expr :: CVXParser E.CVXExpression
  expr = buildExpressionParser table term
          <?> "expression"
  
  -- this function exists since I need to verify that the expression satisfies
  -- the restricted multiply because of arithmetic precedence rules
  cvxExpr :: CVXParser E.CVXExpression
  cvxExpr = do {
    e <- expr;
    if(E.isValidExpr e)
    then
      return e
    else
      fail ("Expression " ++ show e ++ " does not adhere to restricted multiply.")
  }
  
  -- constructors to help build the expression table
  binary name fun assoc 
    = Infix (do{ reservedOp lexer name; return fun }) assoc
  prefix name fun
    = Prefix (do{ reservedOp lexer name; return fun })
  
  -- XXX: precedence ordering is *mathematical* precedence (not C-style)
  table = [ [binary "*" (E.BinaryNode ecosMul) AssocRight],
            [prefix "-" (E.UnaryNode ecosNegate)],
            [binary "+" (E.BinaryNode ecosPlus) AssocLeft, 
             binary "-" (E.BinaryNode ecosMinus) AssocLeft] ] 
  
  -- a term is made up of "(cvxExpr)", functions thereof, parameters, or 
  -- variables
  term = (parens lexer cvxExpr)
      <|> choice (map function (M.keys ecosAtoms))
      <|> try parameter 
      <|> variable
      <|> constant
      <?> "simple expressions"
  
  args :: CVXParser [E.CVXExpression]
  args = do {
    sepBy cvxExpr (comma lexer)
  }
        
  function :: String -> CVXParser E.CVXExpression
  function atomName = 
    let symbol = M.lookup atomName ecosAtoms
        n = case (symbol) of 
          Just x -> E.nargs x
          _ -> 0
    in do {
      reserved lexer atomName;
      p <- parens lexer args;
      case (symbol) of
        Just x ->      
          if (length p /= n) 
            then fail "number of arguments do not agree"
            else case (n) of 
              1 -> return (E.UnaryNode x (p!!0))
              2 -> return (E.BinaryNode x (p!!0) (p!!1))
              _ -> fail "no support for n-ary arguments"
        _ -> fail "no such atom"
    }
  
  variable :: CVXParser E.CVXExpression
  variable = do { 
    s <- identifier lexer;
    t <- getState; 
    case (M.lookup s t) of
      Just (E.Variable name vex sign) 
        -> return (E.Leaf $ E.Variable name vex sign)
      _ -> fail $ "expected variable but got " ++ s 
  }
  
  parameter :: CVXParser E.CVXExpression
  parameter = do { 
    s <- identifier lexer;
    t <- getState; 
    case (M.lookup s t) of
      Just (E.Parameter name vex sign rewrite) 
        -> return (E.Leaf $ E.Parameter name vex sign rewrite)
      _ -> fail $ "expected parameter but got " ++ s 
  }
  
  constant :: CVXParser E.CVXExpression
  constant = do {
    s <- naturalOrFloat lexer;
    if(either (>=0) (>=0.0) s)
    then
      return (E.Leaf $ E.positiveParameter $ (either show show s))
    else
      return (E.Leaf $ E.negativeParameter $ (either show show s))
  }
             
  createVariable :: CVXParser E.CVXSymbol
  createVariable = do { 
    s <- identifier lexer; 
    sign <- optionMaybe modifier;
    return (case (sign) of
      Just E.Positive -> (E.positiveVariable s)
      Just E.Negative -> (E.negativeVariable s)
      _ -> E.variable s)
  } <?> "variable"
  
  createParameter :: CVXParser E.CVXSymbol
  createParameter = do {
    s <- identifier lexer;
    sign <- optionMaybe modifier;
    return (case (sign) of
      Just E.Positive -> (E.positiveParameter s)
      Just E.Negative -> (E.negativeParameter s)
      _ -> E.parameter s)
  } <?> "parameter"
  
  modifier :: CVXParser E.Sign
  modifier = 
    do {
      reserved lexer "positive";
      return E.Positive
    } <|>
    do {
      reserved lexer "negative";
      return E.Negative
    } <?> "modifier"
  
  boolOp :: CVXParser String
  boolOp = do {
    reserved lexer "==";
    return "=="
    } <|> do {
      reserved lexer "<=";
      return "<="
    } <|> do {
      reserved lexer ">=";
      return ">="
    } <?> "boolean operator"
    
  constraint :: CVXParser E.CVXConstraint
  constraint = do {
    lhs <- cvxExpr;
    p <- boolOp;
    rhs <- cvxExpr;
    
    let result = case (p) of
          "==" -> (E.Eq lhs rhs)
          "<=" -> (E.Leq lhs rhs)
          ">=" -> (E.Geq lhs rhs)
    in case (E.vexity result) of
      E.Convex -> return result
      _ -> fail "Not a signed DCP compliant constraint."
  } <?> "constraint"
  
  constraints :: CVXParser [E.CVXConstraint]
  constraints = do { 
    reserved lexer "subject to";
    result <- many constraint;
    return result 
  } <?> "constraints"
  
  objective :: E.CVXSense -> CVXParser E.CVXExpression
  objective v = do {
    obj<-cvxExpr;
    case(E.vexity obj) of
      vex | vex == (E.vexity v) || vex == E.Affine -> return obj
      _ -> fail ("Objective fails to satisfy DCP rule. Not " ++ show v ++ ".")
  } <?> "objective"
  -- 
  -- eol :: CVXParser String
  -- eol = try (string "; ") 
  --   <|> try (string "\r\n") 
  --   <|> try (string "\n\r") 
  --   <|> string ";" 
  --   <|> string "\n"
  --   <|> string "\r"
  --   <?> "end of line"
  
  sense :: CVXParser E.CVXSense
  sense = do {
    reserved lexer "minimize";
    return E.Minimize
    } <|>
    do {
      reserved lexer "maximize";
      return E.Maximize
    } <?> "problem sense (maximize or minimize)"
  
  cvxLine :: CVXParser (Maybe E.CVXProblem)
  cvxLine = 
    do {
      probSense<-sense;
      obj<-objective probSense;
      -- verify that the expression is a valid parse tree
      c <- optionMaybe constraints;
      t <- getState;
      --eol;
      case (c) of
        Just x -> return (Just (E.CVXProblem probSense obj x))
        _ -> return (Just (E.CVXProblem probSense obj []))
    } <|>
    do {
      reserved lexer "parameter";
      p <- createParameter;
      updateState (M.insert (E.name p) p);
      t <- getState;
      --eol;
      return Nothing
    } <|>
    do {
      reserved lexer "variable";
      v <- createVariable;
      updateState (M.insert (E.name v) v);
      t <- getState;
      --eol;
      return Nothing
    } <?> "line"
    -- <|>
    -- do {
    --   obj<-cvxExpr;
    --   --eol;
    --   return (show $ rewrite (E.CVXProblem obj []))
    -- }
  
  cvxEmptyProb = E.CVXProblem E.Minimize (E.Leaf $ E.parameter "0") []
  
  cvxProb :: CVXParser E.CVXProblem
  cvxProb = do {
    whiteSpace lexer;
    result <- many cvxLine;
    eof;
    -- only returns the *first* problem
    return (((fromMaybe cvxEmptyProb).head) $ dropWhile isNothing result)
  } <?> "problem"


