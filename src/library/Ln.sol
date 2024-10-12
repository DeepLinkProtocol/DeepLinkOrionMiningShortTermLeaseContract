// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "abdk-libraries-solidity/ABDKMath64x64.sol";

library LogarithmLibrary {
    uint256 private constant DECIMALS = 1e18; // 用来表示分母，精度为 18 位小数

    //
    //    // 计算自然对数 ln(x)，输入参数为分子 numerator 和分母 denominator
    //    function lnAsFraction(uint256 numeratorInput, uint256 denominatorInput) internal pure returns (uint256 numerator, uint256 denominator) {
    //        require(numeratorInput > 0 && denominatorInput > 0, "Numerator and denominator must be greater than 0");
    //
    //        // 将分子/分母转换为 64.64 固定点格式
    //        int128 fraction = ABDKMath64x64.divu(numeratorInput, denominatorInput);
    //
    //        // 计算自然对数 ln(fraction)
    //        int128 lnResult = ABDKMath64x64.ln(fraction);
    //
    //        // 将 ln(fraction) 的结果乘以 DECIMALS，表示为高精度小数的整数部分
    //        int128 scaledResult = ABDKMath64x64.mul(lnResult, ABDKMath64x64.fromUInt(DECIMALS));
    //
    //        // 将结果转换为 uint256 表示
    //        numerator = uint256(int256(scaledResult));  // 分子
    //        denominator = DECIMALS;  // 分母为 DECIMALS，表示小数精度为 18 位
    //    }
    //    }

    using ABDKMath64x64 for int128;

    /**
     * @dev 计算 ln(fraction) = ln(numerator/denominator)
     * @param numerator uint256类型的分子
     * @param denominator uint256类型的分母
     * @return lnNumerator 计算出的自然对数的分子（精度为10^18）
     * @return lnDenominator 计算出的自然对数的分母（精度为10^18，通常为 10^18）
     */
    function lnAsFraction(uint256 numerator, uint256 denominator)
        internal
        pure
        returns (uint256 lnNumerator, uint256 lnDenominator)
    {
        require(numerator > 0, "Numerator must be greater than 0");
        require(denominator > 0, "Denominator must be greater than 0");

        // 将分子和分母转换为 64.64 固定点数格式
        int128 fraction = ABDKMath64x64.divu(numerator, denominator);

        // 直接计算 ln(fraction)
        int128 lnValue = ABDKMath64x64.ln(fraction);

        // 将 64.64 固定点格式的结果转换为分子和分母，乘以 10^18 以获得高精度结果
        (lnNumerator, lnDenominator) = from64x64ToScaledFraction(lnValue, 10 ** 18);
    }

    /**
     * @dev 将 64.64 固定点格式转换为缩放后的分子和分母
     * @param value 64.64 固定点格式的值
     * @param scaleFactor 缩放因子，比如 10^18
     * @return numerator 缩放后的分子
     * @return denominator 缩放后的分母
     */
    function from64x64ToScaledFraction(int128 value, uint256 scaleFactor)
        internal
        pure
        returns (uint256 numerator, uint256 denominator)
    {
        numerator = uint256(int256(value)) * scaleFactor >> 64; // 转换为缩放后的分子
        denominator = scaleFactor; // 分母等于缩放因子
    }
}
