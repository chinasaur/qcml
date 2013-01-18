{--

Copyright (c) 2012-2013, Eric Chu (eytchu@gmail.com)
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met: 

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer. 
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution. 

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

The views and conclusions contained in the software and documentation are
those of the authors and should not be interpreted as representing official
policies, either expressed or implied, of the FreeBSD Project.

--}

module CodeGenerator.MexGenerator(mex, makescoop) where

  import CodeGenerator.CGenerator(varlist,paramlist,paramsigns)
  import CodeGenerator.Common

  import Expression.Expression

  -- this code generator is to be used with the C code generator

  mex :: Codegen -> String
  mex x = unlines $ [
      "#include \"mex.h\"",
      "#include \"solver.h\"",
      "#include <string.h>",
      "",
      "vars v;    // stores result",
      "",
      "void mexFunction( int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[] )",
      "{",
      "  params p;",
      "  pwork *mywork;",
      "  mxArray *xm;",
      "  int i = 0; int j = 0; double *ptr;", -- loop indices
      "",
      "  int numerr = 0;",
      "  mxArray *outvar;",
      "  mxArray *tinfos;",
      profiling,
      argcheck,
      intercalate ("\n") $ zipWith (checkParam) params signs,
      "  mywork = setup(&p);",
      "  if(mywork == NULL) {",
      "    mexErrMsgTxt(\"Internal problem occurred in ECOS while setting up the problem.\\nPlease send a bug report with data to Alexander Domahidi.\\nEmail: domahidi@control.ee.ethz.ch\");",
      "  }",
      "  int flag = 0;",
      "  flag = solve(mywork, &v);",
      createVars vars,
      settings multiplier,
      "  cleanup(mywork);",
      "}"] 
    where multiplier = case(sense (problem x)) of
            Minimize -> 1.0
            Maximize -> -1.0
            Find -> 0.0
          params = paramlist x
          signs = paramsigns x
          vars = varlist x

  profiling :: String
  profiling = unlines [
    "    /* change number of infofields according to profiling setting */    ",
    "#if PROFILING > 0 ",
    "#define NINFOFIELDS 15",
    "#else ",
    "#define NINFOFIELDS 14",
    "#endif",
    "    const char *infofields[NINFOFIELDS] = { \"pcost\",",
    "                                            \"dcost\",",
    "                                            \"pres\",",
    "                                            \"dres\",",
    "                                            \"pinf\",",
    "                                            \"dinf\",",
    "                                            \"pinfres\",",
    "                                            \"dinfres\",",
    "                                            \"gap\",",
    "                                            \"relgap\",   ",
    "                                            \"r0\",",
    "                                            \"numerr\",",
    "                                            \"iter\",",
    "                                            \"infostring\"",
    "#if PROFILING > 0",
    "                                           ,\"timing\"",
    "#endif",
    "                                           };",
    "",
    "#if PROFILING == 1 ",
    "#define NTFIELDS 3",
    "    const char *tinfo[NTFIELDS] = {\"runtime\", \"tsolve\", \"tsetup\"};",
    "#endif            ",
    "    ",
    "#if PROFILING == 2",
    "#define NTFIELDS 8",
    "    const char *tinfo[NTFIELDS] = {\"runtime\", \"tsolve\", \"tsetup\", \"tkktcreate\", \"tkktfactor\", \"tkktsolve\", \"torder\", \"ttranspose\"};",
    "#endif"]

  argcheck :: String
  argcheck = unlines [
    "#ifdef MEXARGMUENTCHECKS",
    "  if( !(nrhs == 1) )",
    "  {",
    "       mexErrMsgTxt(\"scooper only takes 1 argument: scooper(params)\");",
    "  }",
    "  if( nlhs > 2 ) mexErrMsgTxt(\"scooper has up to 2 output arguments only\");",
    "#endif"]

  checkParam :: Param -> Sign -> String
  checkParam p s = unlines $ [
    "  xm = mxGetField(prhs[0], 0, \"" ++ (name p) ++ "\");",
    "  if (xm == NULL) {",
    "    mexErrMsgTxt(\"could not find params." ++ (name p) ++ "\");",
    "  } else {",
    "    if (!( (mxGetM(xm) == " ++ show m ++ ") && (mxGetN(xm) == " ++ show n ++ ") )) mexErrMsgTxt(\"" ++ (name p) ++ " must be size (" ++ show m ++ ", " ++ show n ++ ")\\n\");",
    "    if (mxIsComplex(xm)) mxErrMsgTxt(\"parameter " ++ (name p) ++ " must be real\\n\");",
    "    if (!mxIsClass(xm, \"double\")) mxErrMsgTxt(\"parameter " ++ (name p) ++ " must be full " ++ matOrVec ++ " of doubles\");",
    "    if (mxIsSparse(xm)) mxErrMsgTxt(\"parameter " ++ (name p) ++ " must be full " ++ matOrVec ++ "\");",
    copy,
    "  }"] 
    where (m,n) = (rows p, cols p)
          matOrVec | n == 1 = "vector"
                   | otherwise = "matrix"
          copy | m == 1 && n == 1 = "    p." ++ name p ++ " = *mxGetPr(xm);"
               | n == 1 = "    memcpy(p." ++ (name p) ++ ", mxGetPr(xm), sizeof(double)*" ++ show m ++  ");"
               | otherwise = intercalate ("\n") $ [   -- matlab is in column order instead of row order (like C), so memcpy won't cut it
                  "    ptr = mxGetPr(xm);",
                  "    for(j = 0; j < " ++ show n ++ "; ++j) {",
                  "      for(i = 0; i < " ++ show m ++ "; ++i) {",
                  "        p." ++ name p ++ "[i][j] = *ptr++;",
                  "      }",
                  "    }"] 

  createVars :: [Var] -> String
  createVars vs = unlines $ [
    "  const int num_var_names = " ++ (show $ length vs) ++ ";",
    "  const char *var_names[] = {" ++ intercalate (", ") (map (\x -> "\"" ++ name x ++ "\"") vs) ++ "};",
    "  plhs[0] = mxCreateStructMatrix(1, 1, num_var_names, var_names);",
    intercalate ("\n") $ map createVar vs]

  createVar :: Var -> String
  createVar v = unlines $ [
    "  xm = mxCreateDoubleMatrix(" ++ show m ++ ", " ++ show n ++ ",mxREAL);",
    "  mxSetField(plhs[0], 0, \"" ++ name v ++ "\", xm);",
    copy]
    where copy | m == 1 && n == 1 = "  *mxGetPr(xm) = v." ++ name v ++ ";"
               | n == 1 = "  memcpy(mxGetPr(xm), v." ++ name v ++ ", sizeof(double)*"++ show m ++ ");"
               | otherwise = intercalate ("\n") $ [   -- matlab is in column order instead of row order (like C), so memcpy won't cut it
                  "  ptr = mxGetPr(xm);",
                  "  for(j = 0; j < " ++ show n ++ "; ++j) {",
                  "    for(i = 0; i < " ++ show m ++ "; ++i) {",
                  "      *ptr++ = p." ++ name v ++ "[i][j];",
                  "    }",
                  "  }"] 
          (m,n) = (rows v, cols v)

  settings :: Double -> String
  settings mutiplier = unlines [
    "  if( nlhs == 2 ){",
    "      plhs[1] = mxCreateStructMatrix(1, 1, NINFOFIELDS, infofields);",
    "      ",
    "      /* 1. primal objective */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = " ++ show mutiplier ++ "*((double)mywork->info->pcost);",
    "      mxSetField(plhs[1], 0, \"pcost\", outvar);",
    "      ",
    "      /* 2. dual objective */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->dcost;",
    "      mxSetField(plhs[1], 0, \"dcost\", outvar);",
    "        ",
    "      /* 3. primal residual */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->pres;",
    "      mxSetField(plhs[1], 0, \"pres\", outvar);",
    "        ",
    "      /* 4. dual residual */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->dres;",
    "      mxSetField(plhs[1], 0, \"dres\", outvar);",
    "      ",
    "      /* 5. primal infeasible? */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->pinf;",
    "      mxSetField(plhs[1], 0, \"pinf\", outvar);",
    "      ",
    "      /* 6. dual infeasible? */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->dinf;",
    "      mxSetField(plhs[1], 0, \"dinf\", outvar);",
    "      ",
    "      /* 7. primal infeasibility measure */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->pinfres;",
    "      mxSetField(plhs[1], 0, \"pinfres\", outvar);",
    "      ",
    "      /* 8. dual infeasibility measure */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->dinfres;",
    "      mxSetField(plhs[1], 0, \"dinfres\", outvar);",
    "      ",
    "      /* 9. duality gap */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->gap;",
    "      mxSetField(plhs[1], 0, \"gap\", outvar);",
    "      ",
    "      /* 10. relative duality gap */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->relgap;",
    "      mxSetField(plhs[1], 0, \"relgap\", outvar);",
    "      ",
    "      /* 11. feasibility tolerance??? */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->stgs->feastol;",
    "      mxSetField(plhs[1], 0, \"r0\", outvar);",
    "      ",
    "      /* 12. iterations */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->iter;",
    "      mxSetField(plhs[1], 0, \"iter\", outvar);",
    "      ",
    "      /* 13. infostring */",
    "      switch( flag ){",
    "        case ECOS_OPTIMAL:",
    "              outvar = mxCreateString(\"Optimal solution found\");",
    "              break;",
    "          case ECOS_MAXIT:",
    "              outvar = mxCreateString(\"Maximum number of iterations reached\");",
    "              break;",
    "          case ECOS_PINF:",
    "              outvar = mxCreateString(\"Primal infeasible\");",
    "              break;",
    "          case ECOS_DINF:",
    "              outvar = mxCreateString(\"Dual infeasible\");",
    "              break;",
    "          case ECOS_KKTZERO:",
    "              outvar = mxCreateString(\"Element of D zero during KKT factorization\");",
    "              break;",
    "          case ECOS_OUTCONE:",
    "              outvar = mxCreateString(\"PROBLEM: Mulitpliers leaving the cone\");",
    "              break;",
    "          default:",
    "              outvar = mxCreateString(\"UNKNOWN PROBLEM IN SOLVER\");",
    "      }       ",
    "      mxSetField(plhs[1], 0, \"infostring\", outvar);",
    "        ",
    "#if PROFILING > 0        ",
    "      /* 14. timing information */",
    "      tinfos = mxCreateStructMatrix(1, 1, NTFIELDS, tinfo);",
    "      ",
    "      /* 14.1 --> runtime */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->tsolve + (double)mywork->info->tsetup;",
    "      mxSetField(tinfos, 0, \"runtime\", outvar);",
    "        ",
    "      /* 14.2 --> setup time */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->tsetup;",
    "      mxSetField(tinfos, 0, \"tsetup\", outvar);",
    "        ",
    "      /* 14.3 --> solve time */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->tsolve;",
    "      mxSetField(tinfos, 0, \"tsolve\", outvar);",
    "#if PROFILING > 1        ",
    "        ",
    "      /* 14.4 time to create KKT matrix */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->tkktcreate;",
    "      mxSetField(tinfos, 0, \"tkktcreate\", outvar);",
    "      /* 14.5 time for kkt solve */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->tkktsolve;",
    "      mxSetField(tinfos, 0, \"tkktsolve\", outvar);",
    "      ",
    "      /* 14.6 time for kkt factor */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->tfactor;",
    "      mxSetField(tinfos, 0, \"tkktfactor\", outvar);",
    "        ",
    "      /* 14.7 time for ordering */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->torder;",
    "      mxSetField(tinfos, 0, \"torder\", outvar);",
    "      ",
    "      /* 14.8 time for transposes */",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)mywork->info->ttranspose;",
    "      mxSetField(tinfos, 0, \"ttranspose\", outvar);",
    "#endif       ",
    "        ",
    "      mxSetField(plhs[1], 0, \"timing\", tinfos);        ",
    "#endif        ",
    "        ",
    "      /* 15. numerical error? */",
    "      if( (flag == ECOS_NUMERICS) || (flag == ECOS_OUTCONE) || (flag == ECOS_FATAL) ){",
    "          numerr = 1;",
    "      }",
    "      outvar = mxCreateDoubleMatrix(1, 1, mxREAL);",
    "      *mxGetPr(outvar) = (double)numerr;",
    "      mxSetField(plhs[1], 0, \"numerr\", outvar);        ",
    "  }"]



  makescoop :: String -> Codegen -> String
  makescoop path _ = unlines $ [
    "function makescoop(what)",
    "",
    "if( nargin == 0 )",
        "what = {'all'};",
    "elseif( isempty(strfind(what, 'all')) && ...",
            "isempty(strfind(what, 'ldl')) && ...",
            "isempty(strfind(what, 'amd')) && ...",
            "isempty(strfind(what, 'clean')) && ...",
            "isempty(strfind(what, 'ecos')) && ...",
            "isempty(strfind(what, 'scooper')) && ...",
            "isempty(strfind(what, 'purge')) )",
        "fprintf('No rule to make target \"%s\", exiting.\\n', what);",
    "end",
    "",
    "",
    "if (~isempty (strfind (computer, '64')))",
        "d = '-largeArrayDims -DDLONG -DLDL_LONG';    ",
    "else",
        "d = '-DDLONG -DLDL_LONG';    ",
    "end",
    "",
    "",
    "% ldl solver",
    "if( any(strcmpi(what,'ldl')) || any(strcmpi(what,'all')) )",
        "fprintf('Compiling LDL...');",
        "cmd = sprintf('mex -c -O %s -I" ++ path ++ "/code/external/ldl/include -I"++path++"/code/external/SuiteSparse_config "++path++"/code/external/ldl/src/ldl.c', d);",
        "eval(cmd);",
        "fprintf('\\t\\t\\t[done]\\n');",
    "end",
    "",
    "",
    "% amd (approximate minimum degree ordering)",
    "if( any(strcmpi(what,'amd')) || any(strcmpi(what,'all')) )",
        "fprintf('Compiling AMD...');",
        "i = sprintf ('-I"++path++"/code/external/amd/include -I"++path++"/code/external/SuiteSparse_config') ;",
        "cmd = sprintf ('mex -c -O %s -DMATLAB_MEX_FILE %s', d, i) ;",
        "files = {'amd_order', 'amd_dump', 'amd_postorder', 'amd_post_tree', ...",
                 "'amd_aat', 'amd_2', 'amd_1', 'amd_defaults', 'amd_control', ...",
                 "'amd_info', 'amd_valid', 'amd_global', 'amd_preprocess' } ;",
        "for i = 1 : length (files)",
            "cmd = sprintf ('%s "++path++"/code/external/amd/src/%s.c', cmd, files {i}) ;",
        "end",
        "eval(cmd);",
        "fprintf('\\t\\t\\t[done]\\n');",
    "end",
    "",
    "",
    "% ecos (solver)",
    "if( any(strcmpi(what,'ecos')) || any(strcmpi(what,'all')) ) ",
        "fprintf('Compiling ecos...');",
        "i = sprintf('-I"++path++"/code/include -I"++path++"/code/external/SuiteSparse_config -I"++path++"/code/external/ldl/include -I"++path++"/code/external/amd/include');",
        "cmd = sprintf('mex -c -O %s -DMATLAB_MEX_FILE %s', d, i);",
        "files = {'ecos', 'kkt', 'cone', 'spla', 'timer', 'preproc', 'splamm'};",
        "for i = 1 : length (files)",
            "cmd = sprintf ('%s "++path++"/code/src/%s.c', cmd, files {i}) ;",
        "end",
        "eval(cmd);    ",
        "fprintf('\\t\\t\\t[done]\\n');",
    "end",
    "",
    "",
    "% scooper",
    "if( any(strcmpi(what,'scooper')) || any(strcmpi(what,'all')) )",
        "fprintf('Compiling scooper...');",
        "cmd = sprintf('mex -c -O -DMATLAB_MEX_FILE -DMEXARGMUENTCHECKS %s -I"++path++"/code/include -I"++path++"/code/external/SuiteSparse_config -I"++path++"/code/external/ldl/include -I"++path++"/code/external/amd/include scooper.c', d);",
        "eval(cmd);",
        "cmd = sprintf('mex -c -O -DMATLAB_MEX_FILE -DMEXARGMUENTCHECKS %s -I"++path++"/code/include -I"++path++"/code/external/SuiteSparse_config -I"++path++"/code/external/ldl/include -I"++path++"/code/external/amd/include solver.c', d);",
        "eval(cmd);",
        "fprintf('\\t\\t\\t[done]\\n');",
        "fprintf('Linking...     ');",
        "% clear ecos",
        "if( ispc )",
            "cmd = sprintf('mex %s amd_1.obj amd_2.obj amd_aat.obj amd_control.obj amd_defaults.obj amd_dump.obj amd_global.obj amd_info.obj amd_order.obj amd_post_tree.obj amd_postorder.obj amd_preprocess.obj amd_valid.obj ldl.obj kkt.obj preproc.obj spla.obj cone.obj ecos.obj timer.obj splamm.obj solver.obj scooper.obj -output \"scooper\"', d);",
            "eval(cmd);    ",
        "elseif( ismac )",
            "cmd = sprintf('mex %s -lm amd_1.o   amd_2.o   amd_aat.o   amd_control.o   amd_defaults.o   amd_dump.o   amd_global.o   amd_info.o   amd_order.o   amd_post_tree.o   amd_postorder.o   amd_preprocess.o   amd_valid.o     ldl.o   kkt.o   preproc.o   spla.o   cone.o   ecos.o timer.o   splamm.o   solver.o   scooper.o   -output \"scooper\"', d);",
            "eval(cmd);",
        "elseif( isunix )",
            "cmd = sprintf('mex %s -lm -lrt amd_1.o   amd_2.o   amd_aat.o   amd_control.o   amd_defaults.o   amd_dump.o   amd_global.o   amd_info.o   amd_order.o   amd_post_tree.o   amd_postorder.o   amd_preprocess.o   amd_valid.o     ldl.o   kkt.o   preproc.o   spla.o   cone.o   ecos.o timer.o   splamm.o   solver.o   scooper.o   -output \"scooper\"', d);",
            "eval(cmd);",
        "end",
        "fprintf('\\t\\t\\t\\t[done]\\n');",
    "        ",
    "%     fprintf('Copying MEX file...');",
    "%     clear ecos",
    "%     copyfile(['scooper.',mexext], ['../scooper.',mexext], 'f');",
    "%     % copyfile( 'ecos.m', '../ecos.m','f');",
    "%     fprintf('\\t\\t\\t[done]\\n');",
        "disp('scooper successfully compiled. Happy solving!');",
    "end",
    "",
    "  ",
    "% clean",
    "if( any(strcmpi(what,'clean')) || any(strcmpi(what,'purge')) || any(strcmpi(what,'all')))",
        "fprintf('Cleaning up object files...  ');",
        "if( ispc ), delete('*.obj'); end",
        "if( isunix), delete('*.o'); end",
        "fprintf('\\t[done]\\n');",
    "end",
    "",
    "% purge",
    "if( any(strcmpi(what,'purge')) )",
        "fprintf('Deleting mex file...  ');",
        "if( ispc ), delete(['scooper.',mexext]); end",
        "if( isunix), delete(['scooper.',mexext]); end",
        "fprintf('\\t\\t[done]\\n');",
    "end"]