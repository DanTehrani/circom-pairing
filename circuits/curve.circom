pragma circom 2.0.2;

include "../node_modules/circomlib/circuits/bitify.circom";

include "./bigint.circom";
include "./bigint_func.circom";
include "./fp.circom";
include "./fp2.circom";

// taken from https://zkrepl.dev/?gist=1e0a28ec3cc4967dc0994e30d316a8af
template IsArrayEqual(k){
    signal input in[2][k];
    signal output out;
    component isEqual[k+1];
    var sum = 0;
    for(var i = 0; i < k; i++){
        isEqual[i] = IsEqual();
        isEqual[i].in[0] <== in[0][i];
        isEqual[i].in[1] <== in[1][i];
        sum = sum + isEqual[i].out;
    }

    isEqual[k] = IsEqual();
    isEqual[k].in[0] <== sum;
    isEqual[k].in[1] <== k;
    out <== isEqual[k].out;
}

// in[i] = (x_i, y_i) 
// Implements constraint: (y_1 + y_3) * (x_2 - x_1) - (y_2 - y_1)*(x_1 - x_3) = 0 mod p
// used to show (x1, y1), (x2, y2), (x3, -y3) are co-linear
template PointOnLine(n, k, p) {
    signal input in[3][2][k]; 

    var LOGK = 3;
    assert(k <= 7);
    assert(3*n + 2*LOGK + 2 < 253);

    // AKA check point on line 
    component left = BigMultNoCarry(n, k); // 2k-1 registers in [0, (k+1)2^{2n+1})
    for(var i = 0; i < k; i++){
        left.a[0][i] <== in[0][1][i] + in[2][1][i];
        left.a[1][i] <== 0;
        left.b[0][i] <== in[1][0][i];
        left.b[1][i] <== in[0][0][i]; 
    }

    component right = BigMultNoCarry(n, k); // 2k-1 registers in [0, (k+1)2^{2n+1})
    for(var i = 0; i < k; i++){
        right.a[0][i] <== in[1][1][i];
        right.a[1][i] <== in[0][1][i];
        right.b[0][i] <== in[0][0][i];
        right.b[1][i] <== in[2][0][i];
    }
    
    component diff_red[2]; 
    for(var j=0; j<2; j++){
        diff_red[j] = PrimeReduce(n, k, k-1, p);
        for(var i=0; i<2*k-1; i++)
            diff_red[j].in[i] <== left.out[j][i] + right.out[j^1][i];  
    }
    // diff_red has 2 x k registers in [0, k(k+1)2^{3n+2} < 2^{3n + 2LOGK + 2} )
    component diff_mod = CheckCarryModToZero(n, k, 3*n + 2*LOGK + 2, p);
    for(var j=0; j<2; j++)for(var i=0; i<k; i++)
        diff_mod.in[j][i] <== diff_red[j].out[i]; 
}

// in = (x, y)
// Implements:
// x^3 + ax + b - y^2 = 0 mod p
// Assume: a, b in [0, 2^n) 
template PointOnCurve(n, k, a, b, p){
    signal input in[2][k]; 

    var LOGK = 3;
    assert(k<=7);
    assert(4*n + 3*LOGK + 2 < 253);

    // compute x^3, y^2 
    component x_sq = BigMultShortLong(n, k); // 2k-1 registers in [0, (k+1)2^{2n}) 
    component y_sq = BigMultShortLong(n, k); // 2k-1 registers in [0, (k+1)2^{2n}) 
    for(var i=0; i<k; i++){
        x_sq.a[i] <== in[0][i];
        x_sq.b[i] <== in[0][i];

        y_sq.a[i] <== in[1][i];
        y_sq.b[i] <== in[1][i];
    }
    component x_cu = BigMultShortLong(n, 2*k-1); // 3k-2 registers in [0, (k+1)^2 * 2^{3n}) 
    for(var i=0; i<2*k-1; i++){
        x_cu.a[i] <== x_sq.out[i];
        if(i < k)
            x_cu.b[i] <== in[0][i];
        else
            x_cu.b[i] <== 0;
    }
    // x_cu + a x + b has 3k-2 registers < (k+1)^2 * 2^{3n} + 2^{2n} + 2^n < 2^{3n + 2LOGK + 1} 
    component cu_red = PrimeReduce(n, k, 2*k-2, p);
    for(var i=0; i<3*k-2; i++){
        if(i == 0)
            cu_red.in[i] <== x_cu.out[i] + a * in[0][i] + b; 
        else{
            if(i < k)
                cu_red.in[i] <== x_cu.out[i] + a * in[0][i]; 
            else
                cu_red.in[i] <== x_cu.out[i];
        }
    }
    // cu_red has k registers < (2k-1)*2^{4n + 2LOGK + 1} < 2^{4n + 3LOGK + 2}

    component y_sq_red = PrimeReduce(n, k, k-1, p);
    for(var i=0; i<2*k-1; i++)
        y_sq_red.in[i] <== y_sq.out[i]; 

    component constraint = CheckCarryModToZero(n, k, 4*n + 3*LOGK + 2, p);
    for(var i=0; i<k; i++){
        constraint.in[0][i] <== cu_red.out[i];
        constraint.in[1][i] <== y_sq_red.out[i]; 
    }
}

// in[0] = (x_1, y_1), in[1] = (x_3, y_3) 
// Checks that the line between (x_1, y_1) and (x_3, -y_3) is equal to the tangent line to the elliptic curve at the point (x_1, y_1)
// Implements: 
// (y_1 + y_3) = lambda * (x_1 - x_3)
// where lambda = (3 x_1^2 + a)/(2 y_1) 
// Actual constraint is 2y_1 (y_1 + y_3) = (3 x_1^2 + a ) ( x_1 - x_3 )
template PointOnTangent(n, k, a, p){
    signal input in[2][2][k];
    
    var LOGK = 3;
    assert(k <= 7);
    assert(4*n + 3*LOGK + 3 < 253);
    component x_sq = BigMultShortLong(n, k); // 2k-1 registers in [0, (k+1)2^{2n}) 
    for(var i=0; i<k; i++){
        x_sq.a[i] <== in[0][0][i];
        x_sq.b[i] <== in[0][0][i];
    }
    component right = BigMultNoCarry(n, 2*k-1); // 3k-2 registers in [0, 3*(k+1)^2*2^{3n} + (k+1)2^{2n} ) 
    for(var i=0; i<2*k-1; i++){
        if(i == 0)
            right.a[0][i] <== 3 * x_sq.out[i] + a; // registers in [0, 3*(k+1)2^{2n} + 2^n )  
        else
            right.a[0][i] <== 3 * x_sq.out[i]; 
        right.a[1][i] <== 0;

        if(i < k){
            right.b[0][i] <== in[0][0][i];
            right.b[1][i] <== in[1][0][i]; 
        }else{
            right.b[0][i] <== 0;
            right.b[1][i] <== 0;
        }
    }
    
    component left = BigMultShortLong(n, k); // 2k-1 registers in [0, (k+1) 2^{2n+2})
    for(var i=0; i<k; i++){
        left.a[i] <== 2*in[0][1][i];
        left.b[i] <== in[0][1][i] + in[1][1][i];  
    }
    
    // prime reduce right - left 
    component diff_red[2]; 
    for(var i=0; i<2; i++)
        diff_red[i] = PrimeReduce(n, k, 2*k-2, p);
    for(var i=0; i<3*k-2; i++){
        diff_red[0].in[i] <== right.out[0][i]; 
        if(i < 2*k-1) 
            diff_red[1].in[i] <== right.out[1][i] + left.out[i]; 
        else
            diff_red[1].in[i] <== right.out[1][i];
    }
    // inputs of diff_red has registers in [0, 3*(k+1)^2*2^{3n} + (k+1)2^{2n} + (k+1) 2^{2n+2} < 4*(k+1)^2*2^{3n} <= 2^{3n+2LOGK+2}) 
    // diff_red.out has registers < (2k-1)*2^{4n + 2LOGK + 2} <= 2^{4n + 3LOGK + 3}  
    component constraint = CheckCarryModToZero(n, k, 4*n + 3*LOGK + 3, p);
    for(var i=0; i<k; i++){
        constraint.in[0][i] <== diff_red[0].out[i];
        constraint.in[1][i] <== diff_red[1].out[i]; 
    }
}

// requires x_1 != x_2
// assume p is size k array, the prime that curve lives over 
//
// Implements:
//  Given a = (x_1, y_1) and b = (x_2, y_2), 
//      assume x_1 != x_2 and a != -b, 
//  Find a + b = (x_3, y_3)
// By solving:
//  x_1 + x_2 + x_3 - lambda^2 = 0 mod p
//  y_3 = lambda (x_1 - x_3) - y_1 mod p
//  where lambda = (y_2-y_1)/(x_2-x_1) is the slope of the line between (x_1, y_1) and (x_2, y_2)
// these equations are equivalent to:
//  (x_1 + x_2 + x_3)*(x_2 - x_1)^2 = (y_2 - y_1)^2 mod p
//  (y_1 + y_3)*(x_2 - x_1) = (y_2 - y_1)*(x_1 - x_3) mod p
template EllipticCurveAddUnequal(n, k, p) { // changing q's to p's for my sanity
    signal input a[2][k];
    signal input b[2][k];

    signal output out[2][k];

    var LOGK = 3;
    assert(k <= 7);
    assert(4*n + 3*LOGK +4 < 253);

    // precompute lambda and x_3 and then y_3
    var dy[20] = long_sub_mod(n, k, b[1], a[1], p);
    var dx[20] = long_sub_mod(n, k, b[0], a[0], p); 
    var dx_inv[20] = mod_inv(n, k, dx, p);
    var lambda[20] = prod_mod(n, k, dy, dx_inv, p);
    var lambda_sq[20] = prod_mod(n, k, lambda, lambda, p);
    // out[0] = x_3 = lamb^2 - a[0] - b[0] % p
    // out[1] = y_3 = lamb * (a[0] - x_3) - a[1] % p
    var x3[20] = long_sub_mod(n, k, long_sub_mod(n, k, lambda_sq, a[0], p), b[0], p);
    var y3[20] = long_sub_mod(n, k, prod_mod(n, k, lambda, long_sub_mod(n, k, a[0], x3, p), p), a[1], p);

    for(var i = 0; i < k; i++){
        out[0][i] <-- x3[i];
        out[1][i] <-- y3[i];
    }
    
    // constrain x_3 by CUBIC (x_1 + x_2 + x_3) * (x_2 - x_1)^2 - (y_2 - y_1)^2 = 0 mod p
    
    component dx_sq = BigMultNoCarry(n, k); // 2k-1 registers in [0, (k+1)*2^{2n+1} )
    component dy_sq = BigMultNoCarry(n, k); // 2k-1 registers in [0, (k+1)*2^{2n+1} )
    for(var i = 0; i < k; i++){
        dx_sq.a[0][i] <== b[0][i];
        dx_sq.a[1][i] <== a[0][i];
        dx_sq.b[0][i] <== b[0][i];
        dx_sq.b[1][i] <== a[0][i];

        dy_sq.a[0][i] <== b[1][i];
        dy_sq.a[1][i] <== a[1][i];
        dy_sq.b[0][i] <== b[1][i];
        dy_sq.b[1][i] <== a[1][i];
    } 

    // x_1 + x_2 + x_3 has registers in [0, 3*2^n) 
    component cubic = BigMultNoCarry(n, 2*k-1); // 3k-2 registers in [0, 3 * (k+1)^2 * 2^{3n+1} ) 
    for(var i=0; i<2*k-1; i++){
        if(i < k)
            cubic.a[0][i] <== a[0][i] + b[0][i] + out[0][i]; 
        else
            cubic.a[0][i] <== 0;
        cubic.a[1][i] <== 0;
 
        cubic.b[0][i] <== dx_sq.out[0][i];
        cubic.b[1][i] <== dx_sq.out[1][i];
    }

    component cubic_red[2]; 
    for(var j=0; j<2; j++){
        cubic_red[j] = PrimeReduce(n, k, 2*k-2, p);
        for(var i=0; i<2*k-1; i++)
            cubic_red[j].in[i] <== cubic.out[j][i] + dy_sq.out[j ^ 1][i]; // registers in [0, 3*(k+1)^2*2^{3n+1} + (k+1)*2^{2n+1} < 2^{3n+2LOGK+3} )
        // j ^ 1 flips the bit so has the effect of subtracting  
        for(var i=2*k-1; i<3*k-2; i++)
            cubic_red[j].in[i] <== cubic.out[j][i]; 
    }
    // cubic_red has 2 x k registers in [0, (2k-1) 2^{4n+2LOGK+3} < 2^{4n+3LOGK+4} )
    
    component cubic_mod = CheckCarryModToZero(n, k, 4*n + 3*LOGK + 4, p);
    for(var j=0; j<2; j++)for(var i=0; i<k; i++)
        cubic_mod.in[j][i] <== cubic_red[j].out[i]; 
    // END OF CONSTRAINING x3
    
    // constrain y_3 by (y_1 + y_3) * (x_2 - x_1) = (y_2 - y_1)*(x_1 - x_3) mod p
    component y_constraint = PointOnLine(n, k, p); // 2k-1 registers in [0, (k+1)2^{2n+1})
    for(var i = 0; i < k; i++)for(var j=0; j<2; j++){
        y_constraint.in[0][j][i] <== a[j][i];
        y_constraint.in[1][j][i] <== b[j][i];
        y_constraint.in[2][j][i] <== out[j][i];
    }
    // END OF CONSTRAINING y3

    // check if out[][] has registers in [0, 2^n) and each out[i] is in [0, p)
    // re-using Fp2 code by considering (x_3, y_3) as a 2d-vector over Fp
    component range_check = CheckValidFp2(n, k, p);
    for(var j=0; j<2; j++)for(var i=0; i<k; i++)
        range_check.in[j][i] <== out[j][i];
}


// Elliptic curve is E : y**2 = x**3 + ax + b
// assuming a < 2^n for now
// Note that for BLS12-381, a = 0, b = 4

// Implements:
// computing 2P on elliptic curve E for P = (x_1, y_1)
// formula from https://crypto.stanford.edu/pbc/notes/elliptic/explicit.html
// x_1 = in[0], y_1 = in[1]
// assume y_1 != 0 (otherwise 2P = O)

// lamb =  (3x_1^2 + a) / (2 y_1) % p
// x_3 = out[0] = lambda^2 - 2 x_1 % p
// y_3 = out[1] = lambda (x_1 - x_3) - y_1 % p

// We precompute (x_3, y_3) and then constrain by showing that:
// * (x_3, y_3) is a valid point on the curve 
// * the slope (y_3 - y_1)/(x_3 - x_1) equals 
// * x_1 != x_3 
template EllipticCurveDouble(n, k, a, b, p) {
    signal input in[2][k];
    signal output out[2][k];

    /* 
    var LOGK = 3;
    assert(k <= 7);
    assert(4*n + 3*LOGK + 3 < 253);
    */

    var long_a[20];
    var long_3[20];
    long_a[0] = a;
    long_3[0] = 3;
    for (var i = 1; i < k; i++) {
        long_a[i] = 0;
        long_3[i] = 0;
    }

    // precompute lambda 
    var lamb_num[20] = long_add_mod(n, k, long_a, prod_mod(n, k, long_3, prod_mod(n, k, in[0], in[0], p), p), p);
    var lamb_denom[20] = long_add_mod(n, k, in[1], in[1], p);
    var lamb[20] = prod_mod(n, k, lamb_num, mod_inv(n, k, lamb_denom, p), p);

    // precompute x_3, y_3
    var x3[20] = long_sub_mod(n, k, prod_mod(n, k, lamb, lamb, p), long_add_mod(n, k, in[0], in[0], p), p);
    var y3[20] = long_sub_mod(n, k, prod_mod(n, k, lamb, long_sub_mod(n, k, in[0], x3, p), p), in[1], p);
    
    for(var i=0; i<k; i++){
        out[0][i] <-- x3[i];
        out[1][i] <-- y3[i];
    }
    // check if out[][] has registers in [0, 2^n) and each out[i] is in [0, p)
    // re-using Fp2 code by considering (x_3, y_3) as a 2d-vector over Fp
    component range_check = CheckValidFp2(n, k, p);
    for(var j=0; j<2; j++)for(var i=0; i<k; i++)
        range_check.in[j][i] <== out[j][i];

    component point_on_tangent = PointOnTangent(n, k, a, p);
    for(var j=0; j<2; j++)for(var i=0; i<k; i++){
        point_on_tangent.in[0][j][i] <== in[j][i];
        point_on_tangent.in[1][j][i] <== out[j][i];
    }
    
    component point_on_curve = PointOnCurve(n, k, a, b, p);
    for(var j=0; j<2; j++)for(var i=0; i<k; i++)
        point_on_curve.in[j][i] <== out[j][i];
    
    component x3_eq_x1 = IsArrayEqual(k);
    for(var i = 0; i < k; i++){
        x3_eq_x1.in[0][i] <== out[0][i];
        x3_eq_x1.in[1][i] <== in[0][i];
    }
    x3_eq_x1.out === 0;
}
