function errs = ecos_tester()
    clear all;
%    randn('state', 0);
%    rand('state', 0);
%    cvx_precision best
    cvx_quiet true
    cvx_solver sdpt3
    
    % biggest problem seems to be that it doesn't detect infeasibility and
    % unboundedness
        
    N = 10; % number of tests (for problems with random data)
    
    fprintf('Running tests. Ensure that ECOS_CREATOR was previously run.\n\n');
    try
        errs.LS = run_test('least_squares', N);
        errs.GEOMEAN = run_test('geometric_mean',1);
        errs.LP = run_test('lp', N);
        errs.PATHLP = run_test('pathological_lp',1);    % actually, CVX is *wrong* here
        errs.QOL = run_test('quadratic_over_linear',1);
        errs.INV = run_test('inv_prob', 1);
        errs.MINMAX = run_test('min_max',1); 
        errs.RLS = run_test('robust_ls', N);
        errs.MPC = run_test('ecos_mpc', 1);
        errs.LASSO = run_test('lasso', N);
        errs.PORT = run_test('portfolio', N);
        errs.SVM = run_test('svm', N);
        errs.CHEB = run_test('chebyshev', 1);
    catch e
        disp('FAILED RUN: possibly forgot to run ecos_creator.');
        cd ..   % return to top level directory
        e.message
    end

end

function error_msgs = run_test(directory, N)
    RELTOL = 1e-5;
    global CONELP_LINSOLVER_;
    fail.ecos = 0; fail.conelp_ldlsparse = 0; 
    fail.conelp_backslash = 0; fail.c = 0;
    fail.cvxsocp = 0; fail.rome = 0;
    
    ave_runtime.ecos = 0;
    ave_runtime.conelp_ldlsparse = 0;
    ave_runtime.conelp_backslash = 0;
    ave_runtime.c = 0;
    ave_runtime.cvxsocp = 0;
    ave_runtime.rome = 0;
    
    error_msgs.ecos = {};
    error_msgs.conelp_ldlsparse = {};
    error_msgs.conelp_backslash = {};
    error_msgs.c = {};
    error_msgs.cvxsocp = {};
    error_msgs.rome = {};
    
    s = sprintf('Comparing all solvers for %s to CVX.', upper(directory));
    fprintf('%s\n',s);
    divider = s;
    for i = 1:length(divider)
        divider(i) = '=';
    end
    fprintf('%s\n',divider);
    
    cd(directory)
    
    delStr = '';
    for i = 1:N,
        data;
        eval(directory)
        v1 = cvx_optval;
        %x_cvx = x;
        sol_status = cvx_status;

        clear x
        try
            tic;
            evalc('ecos_solver'); v2 = ecos_optval;
            ave_runtime.ecos = ave_runtime.ecos + 1000*toc/N;
            if(fail_test(sol_status, info_, v1, v2, RELTOL)) 
                fail.ecos = fail.ecos + 1;
            end
        catch myERROR
            fail.ecos = fail.ecos+1;
            error_msgs.ecos{end+1} = myERROR;
        end
        
        try
            CONELP_LINSOLVER_ = 'ldlsparse';    % used in conelp
            tic;
            evalc('conelp_solver'); v2 = ecos_optval;
            ave_runtime.conelp_ldlsparse = ave_runtime.conelp_ldlsparse + 1000*toc/N;
            if(fail_test(sol_status, info_, v1, v2, RELTOL)) 
                fail.conelp_ldlsparse = fail.conelp_ldlsparse + 1;
            end
        catch myERROR
            fail.conelp_ldlsparse = fail.conelp_ldlsparse + 1;
            error_msgs.conelp_ldlsparse{end+1} = myERROR;
        end
        
        try
            CONELP_LINSOLVER_ = 'backslash';    % used in conelp
            tic;
            evalc('conelp_solver'); v2 = ecos_optval;
            ave_runtime.conelp_backslash = ave_runtime.conelp_backslash + 1000*toc/N;
            if(fail_test(sol_status, info_, v1, v2, RELTOL)) 
                fail.conelp_backslash = fail.conelp_backslash + 1;
            end
        catch myERROR
            fail.conelp_backslash = fail.conelp_backslash + 1;
            error_msgs.conelp_backslash{end+1} = myERROR;
        end
        
        try
            tic;
            evalc('cvxsocp_solver'); v2 = ecos_optval;
            ave_runtime.cvxsocp = ave_runtime.cvxsocp + 1000*toc/N;
            if(~(strcmp(sol_status,cvx_status)) || (abs(v1 - v2) >= RELTOL*abs(v1)))
                fail.cvxsocp = fail.cvxsocp + 1;
            end
        catch myERROR
            fail.cvxsocp = fail.cvxsocp + 1;
            error_msgs.cvxsocp{end+1} = myERROR;
        end
        
        try
            tic;
            evalc('rome_solver'); v2 = scoop_optval;
            ave_runtime.rome = ave_runtime.rome + 1000*toc/N;
            if(~(strcmp(lower(scoop_status),lower(sol_status))) || (abs(v1 - v2) >= RELTOL*abs(v1)))
                fail.rome = fail.rome + 1;
            end
        catch myERROR
            fail.rome = fail.rome + 1;
            error_msgs.rome{end+1} = myERROR;
        end
        
        try
            tic;
            evalc('[sols,info_] = scooper(params)'); v2 = info_.pcost;
            ave_runtime.c = ave_runtime.c + 1000*toc/N;
            if(fail_test(sol_status, info_, v1, v2, RELTOL)) 
                fail.c = fail.c + 1;
            end
        catch myERROR
            fail.c = fail.c + 1;
            error_msgs.c{end+1} = myERROR;
        end
        
        bar = repmat(sprintf('='),1,round(i/N*30));
        msg = sprintf('[%-30s] %d/%d', bar, i, N);
        fprintf([delStr, msg]);
        delStr = repmat(sprintf('\b'), 1, length(msg));
        
    end
    fprintf('\n# FAIL (RELTOL=%f) out of %d trials....\n', RELTOL, N);
    disp(fail)
    
    fprintf('\nAVERAGE runtime (in ms) for solver out of %d trials....\n', N);
    disp(ave_runtime)
        
    cd ..
end

function failed = fail_test(status, info, v1, v2, tol)
    switch lower(status)
        case 'solved'
            failed = (abs(v1 - v2) >= tol*abs(v1));
        case 'infeasible'
            failed = ~(info.pinf == 1 && info.dinf == 0);
        case 'unbounded'
            failed = ~(info.dinf == 1 && info.pinf == 0);
        otherwise
            error(['unknown test for ' status '.']);
    end
end

%
% A defined as --
% rowidx = 
% vals = 
% col_startidx = [0,4,6,7,9,10]
%
% G(14:..., 10:...) = A
% G_rowidx
% G_vals
% G_col_startidx =
%

% i can store each column independently?
%
% in C code, the matrix A is "static" (just malloc the memory needed for it,
% since you'll know nnz at runtime)--static in the sense that the memory
% allocation only occurs once.
%
% elements should be copied based on "nnz" per "col" of inserted elements
%

% this means params needs to store in CCS and also have m,n vals for
% matrices...

% going to look something like this... (assuming A is an n x 2 matrix)
% G_vals = [...., params.A.col(0), other stuff, params.A.col(1), .... ]
% so G_vals and G_rowidx = #constants + nnz(A) (which is at the end of the
% matrix)
%
% can emit static stuff, like G_vals[0] = 1, G_vals[1] = 3, etc.
%
% when having to *copy* over a matrix
%

% memcpy code...
% for(i = (start idx of col 0):(start idx of col 1) - 1)
%   G_rowidx[k] = A_rowidx[i] + row offset
%   G_vals[k] = A_vals[i]
%   k++
% basically, this is
%
% XXX/TODO: THIS IS THE PIECE OF CODE TO USE (and, yes, all caps is warranted here!) 
% =========================================================================
% memcpy(from &A_rowidx[i], to &G_rowidx[k], length=(start idx of col 1) - (start idx of col 0))
% increment k by length
% =========================================================================

%
% depending on the compiler (and the machine architecture), memcpy could be
% faster than for loops, and for loops could be faster than memcpy.
%
% for simplicity, we'll stick with memcpy's (since, on average, it's
% fastest, without needing to play with compiler flags).
%
