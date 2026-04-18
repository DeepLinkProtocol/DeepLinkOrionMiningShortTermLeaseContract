// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// lib/abdk-libraries-solidity/ABDKMath64x64.sol

/*
 * ABDK Math 64.64 Smart Contract Library.  Copyright © 2019 by ABDK Consulting.
 * Author: Mikhail Vladimirov <mikhail.vladimirov@gmail.com>
 */

/**
 * Smart contract library of mathematical functions operating with signed
 * 64.64-bit fixed point numbers.  Signed 64.64-bit fixed point number is
 * basically a simple fraction whose numerator is signed 128-bit integer and
 * denominator is 2^64.  As long as denominator is always the same, there is no
 * need to store it, thus in Solidity signed 64.64-bit fixed point numbers are
 * represented by int128 type holding only the numerator.
 */
library ABDKMath64x64 {
  /*
   * Minimum value signed 64.64-bit fixed point number may have. 
   */
  int128 private constant MIN_64x64 = -0x80000000000000000000000000000000;

  /*
   * Maximum value signed 64.64-bit fixed point number may have. 
   */
  int128 private constant MAX_64x64 = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

  /**
   * Convert signed 256-bit integer number into signed 64.64-bit fixed point
   * number.  Revert on overflow.
   *
   * @param x signed 256-bit integer number
   * @return signed 64.64-bit fixed point number
   */
  function fromInt (int256 x) internal pure returns (int128) {
    unchecked {
      require (x >= -0x8000000000000000 && x <= 0x7FFFFFFFFFFFFFFF);
      return int128 (x << 64);
    }
  }

  /**
   * Convert signed 64.64 fixed point number into signed 64-bit integer number
   * rounding down.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64-bit integer number
   */
  function toInt (int128 x) internal pure returns (int64) {
    unchecked {
      return int64 (x >> 64);
    }
  }

  /**
   * Convert unsigned 256-bit integer number into signed 64.64-bit fixed point
   * number.  Revert on overflow.
   *
   * @param x unsigned 256-bit integer number
   * @return signed 64.64-bit fixed point number
   */
  function fromUInt (uint256 x) internal pure returns (int128) {
    unchecked {
      require (x <= 0x7FFFFFFFFFFFFFFF);
      return int128 (int256 (x << 64));
    }
  }

  /**
   * Convert signed 64.64 fixed point number into unsigned 64-bit integer
   * number rounding down.  Revert on underflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @return unsigned 64-bit integer number
   */
  function toUInt (int128 x) internal pure returns (uint64) {
    unchecked {
      require (x >= 0);
      return uint64 (uint128 (x >> 64));
    }
  }

  /**
   * Convert signed 128.128 fixed point number into signed 64.64-bit fixed point
   * number rounding down.  Revert on overflow.
   *
   * @param x signed 128.128-bin fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function from128x128 (int256 x) internal pure returns (int128) {
    unchecked {
      int256 result = x >> 64;
      require (result >= MIN_64x64 && result <= MAX_64x64);
      return int128 (result);
    }
  }

  /**
   * Convert signed 64.64 fixed point number into signed 128.128 fixed point
   * number.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 128.128 fixed point number
   */
  function to128x128 (int128 x) internal pure returns (int256) {
    unchecked {
      return int256 (x) << 64;
    }
  }

  /**
   * Calculate x + y.  Revert on overflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @param y signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function add (int128 x, int128 y) internal pure returns (int128) {
    unchecked {
      int256 result = int256(x) + y;
      require (result >= MIN_64x64 && result <= MAX_64x64);
      return int128 (result);
    }
  }

  /**
   * Calculate x - y.  Revert on overflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @param y signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function sub (int128 x, int128 y) internal pure returns (int128) {
    unchecked {
      int256 result = int256(x) - y;
      require (result >= MIN_64x64 && result <= MAX_64x64);
      return int128 (result);
    }
  }

  /**
   * Calculate x * y rounding down.  Revert on overflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @param y signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function mul (int128 x, int128 y) internal pure returns (int128) {
    unchecked {
      int256 result = int256(x) * y >> 64;
      require (result >= MIN_64x64 && result <= MAX_64x64);
      return int128 (result);
    }
  }

  /**
   * Calculate x * y rounding towards zero, where x is signed 64.64 fixed point
   * number and y is signed 256-bit integer number.  Revert on overflow.
   *
   * @param x signed 64.64 fixed point number
   * @param y signed 256-bit integer number
   * @return signed 256-bit integer number
   */
  function muli (int128 x, int256 y) internal pure returns (int256) {
    unchecked {
      if (x == MIN_64x64) {
        require (y >= -0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF &&
          y <= 0x1000000000000000000000000000000000000000000000000);
        return -y << 63;
      } else {
        bool negativeResult = false;
        if (x < 0) {
          x = -x;
          negativeResult = true;
        }
        if (y < 0) {
          y = -y; // We rely on overflow behavior here
          negativeResult = !negativeResult;
        }
        uint256 absoluteResult = mulu (x, uint256 (y));
        if (negativeResult) {
          require (absoluteResult <=
            0x8000000000000000000000000000000000000000000000000000000000000000);
          return -int256 (absoluteResult); // We rely on overflow behavior here
        } else {
          require (absoluteResult <=
            0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
          return int256 (absoluteResult);
        }
      }
    }
  }

  /**
   * Calculate x * y rounding down, where x is signed 64.64 fixed point number
   * and y is unsigned 256-bit integer number.  Revert on overflow.
   *
   * @param x signed 64.64 fixed point number
   * @param y unsigned 256-bit integer number
   * @return unsigned 256-bit integer number
   */
  function mulu (int128 x, uint256 y) internal pure returns (uint256) {
    unchecked {
      if (y == 0) return 0;

      require (x >= 0);

      uint256 lo = (uint256 (int256 (x)) * (y & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)) >> 64;
      uint256 hi = uint256 (int256 (x)) * (y >> 128);

      require (hi <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
      hi <<= 64;

      require (hi <=
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF - lo);
      return hi + lo;
    }
  }

  /**
   * Calculate x / y rounding towards zero.  Revert on overflow or when y is
   * zero.
   *
   * @param x signed 64.64-bit fixed point number
   * @param y signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function div (int128 x, int128 y) internal pure returns (int128) {
    unchecked {
      require (y != 0);
      int256 result = (int256 (x) << 64) / y;
      require (result >= MIN_64x64 && result <= MAX_64x64);
      return int128 (result);
    }
  }

  /**
   * Calculate x / y rounding towards zero, where x and y are signed 256-bit
   * integer numbers.  Revert on overflow or when y is zero.
   *
   * @param x signed 256-bit integer number
   * @param y signed 256-bit integer number
   * @return signed 64.64-bit fixed point number
   */
  function divi (int256 x, int256 y) internal pure returns (int128) {
    unchecked {
      require (y != 0);

      bool negativeResult = false;
      if (x < 0) {
        x = -x; // We rely on overflow behavior here
        negativeResult = true;
      }
      if (y < 0) {
        y = -y; // We rely on overflow behavior here
        negativeResult = !negativeResult;
      }
      uint128 absoluteResult = divuu (uint256 (x), uint256 (y));
      if (negativeResult) {
        require (absoluteResult <= 0x80000000000000000000000000000000);
        return -int128 (absoluteResult); // We rely on overflow behavior here
      } else {
        require (absoluteResult <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        return int128 (absoluteResult); // We rely on overflow behavior here
      }
    }
  }

  /**
   * Calculate x / y rounding towards zero, where x and y are unsigned 256-bit
   * integer numbers.  Revert on overflow or when y is zero.
   *
   * @param x unsigned 256-bit integer number
   * @param y unsigned 256-bit integer number
   * @return signed 64.64-bit fixed point number
   */
  function divu (uint256 x, uint256 y) internal pure returns (int128) {
    unchecked {
      require (y != 0);
      uint128 result = divuu (x, y);
      require (result <= uint128 (MAX_64x64));
      return int128 (result);
    }
  }

  /**
   * Calculate -x.  Revert on overflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function neg (int128 x) internal pure returns (int128) {
    unchecked {
      require (x != MIN_64x64);
      return -x;
    }
  }

  /**
   * Calculate |x|.  Revert on overflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function abs (int128 x) internal pure returns (int128) {
    unchecked {
      require (x != MIN_64x64);
      return x < 0 ? -x : x;
    }
  }

  /**
   * Calculate 1 / x rounding towards zero.  Revert on overflow or when x is
   * zero.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function inv (int128 x) internal pure returns (int128) {
    unchecked {
      require (x != 0);
      int256 result = int256 (0x100000000000000000000000000000000) / x;
      require (result >= MIN_64x64 && result <= MAX_64x64);
      return int128 (result);
    }
  }

  /**
   * Calculate arithmetics average of x and y, i.e. (x + y) / 2 rounding down.
   *
   * @param x signed 64.64-bit fixed point number
   * @param y signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function avg (int128 x, int128 y) internal pure returns (int128) {
    unchecked {
      return int128 ((int256 (x) + int256 (y)) >> 1);
    }
  }

  /**
   * Calculate geometric average of x and y, i.e. sqrt (x * y) rounding down.
   * Revert on overflow or in case x * y is negative.
   *
   * @param x signed 64.64-bit fixed point number
   * @param y signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function gavg (int128 x, int128 y) internal pure returns (int128) {
    unchecked {
      int256 m = int256 (x) * int256 (y);
      require (m >= 0);
      require (m <
          0x4000000000000000000000000000000000000000000000000000000000000000);
      return int128 (sqrtu (uint256 (m)));
    }
  }

  /**
   * Calculate x^y assuming 0^0 is 1, where x is signed 64.64 fixed point number
   * and y is unsigned 256-bit integer number.  Revert on overflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @param y uint256 value
   * @return signed 64.64-bit fixed point number
   */
  function pow (int128 x, uint256 y) internal pure returns (int128) {
    unchecked {
      bool negative = x < 0 && y & 1 == 1;

      uint256 absX = uint128 (x < 0 ? -x : x);
      uint256 absResult;
      absResult = 0x100000000000000000000000000000000;

      if (absX <= 0x10000000000000000) {
        absX <<= 63;
        while (y != 0) {
          if (y & 0x1 != 0) {
            absResult = absResult * absX >> 127;
          }
          absX = absX * absX >> 127;

          if (y & 0x2 != 0) {
            absResult = absResult * absX >> 127;
          }
          absX = absX * absX >> 127;

          if (y & 0x4 != 0) {
            absResult = absResult * absX >> 127;
          }
          absX = absX * absX >> 127;

          if (y & 0x8 != 0) {
            absResult = absResult * absX >> 127;
          }
          absX = absX * absX >> 127;

          y >>= 4;
        }

        absResult >>= 64;
      } else {
        uint256 absXShift = 63;
        if (absX < 0x1000000000000000000000000) { absX <<= 32; absXShift -= 32; }
        if (absX < 0x10000000000000000000000000000) { absX <<= 16; absXShift -= 16; }
        if (absX < 0x1000000000000000000000000000000) { absX <<= 8; absXShift -= 8; }
        if (absX < 0x10000000000000000000000000000000) { absX <<= 4; absXShift -= 4; }
        if (absX < 0x40000000000000000000000000000000) { absX <<= 2; absXShift -= 2; }
        if (absX < 0x80000000000000000000000000000000) { absX <<= 1; absXShift -= 1; }

        uint256 resultShift = 0;
        while (y != 0) {
          require (absXShift < 64);

          if (y & 0x1 != 0) {
            absResult = absResult * absX >> 127;
            resultShift += absXShift;
            if (absResult > 0x100000000000000000000000000000000) {
              absResult >>= 1;
              resultShift += 1;
            }
          }
          absX = absX * absX >> 127;
          absXShift <<= 1;
          if (absX >= 0x100000000000000000000000000000000) {
              absX >>= 1;
              absXShift += 1;
          }

          y >>= 1;
        }

        require (resultShift < 64);
        absResult >>= 64 - resultShift;
      }
      int256 result = negative ? -int256 (absResult) : int256 (absResult);
      require (result >= MIN_64x64 && result <= MAX_64x64);
      return int128 (result);
    }
  }

  /**
   * Calculate sqrt (x) rounding down.  Revert if x < 0.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function sqrt (int128 x) internal pure returns (int128) {
    unchecked {
      require (x >= 0);
      return int128 (sqrtu (uint256 (int256 (x)) << 64));
    }
  }

  /**
   * Calculate binary logarithm of x.  Revert if x <= 0.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function log_2 (int128 x) internal pure returns (int128) {
    unchecked {
      require (x > 0);

      int256 msb = 0;
      int256 xc = x;
      if (xc >= 0x10000000000000000) { xc >>= 64; msb += 64; }
      if (xc >= 0x100000000) { xc >>= 32; msb += 32; }
      if (xc >= 0x10000) { xc >>= 16; msb += 16; }
      if (xc >= 0x100) { xc >>= 8; msb += 8; }
      if (xc >= 0x10) { xc >>= 4; msb += 4; }
      if (xc >= 0x4) { xc >>= 2; msb += 2; }
      if (xc >= 0x2) msb += 1;  // No need to shift xc anymore

      int256 result = msb - 64 << 64;
      uint256 ux = uint256 (int256 (x)) << uint256 (127 - msb);
      for (int256 bit = 0x8000000000000000; bit > 0; bit >>= 1) {
        ux *= ux;
        uint256 b = ux >> 255;
        ux >>= 127 + b;
        result += bit * int256 (b);
      }

      return int128 (result);
    }
  }

  /**
   * Calculate natural logarithm of x.  Revert if x <= 0.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function ln (int128 x) internal pure returns (int128) {
    unchecked {
      require (x > 0);

      return int128 (int256 (
          uint256 (int256 (log_2 (x))) * 0xB17217F7D1CF79ABC9E3B39803F2F6AF >> 128));
    }
  }

  /**
   * Calculate binary exponent of x.  Revert on overflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function exp_2 (int128 x) internal pure returns (int128) {
    unchecked {
      require (x < 0x400000000000000000); // Overflow

      if (x < -0x400000000000000000) return 0; // Underflow

      uint256 result = 0x80000000000000000000000000000000;

      if (x & 0x8000000000000000 > 0)
        result = result * 0x16A09E667F3BCC908B2FB1366EA957D3E >> 128;
      if (x & 0x4000000000000000 > 0)
        result = result * 0x1306FE0A31B7152DE8D5A46305C85EDEC >> 128;
      if (x & 0x2000000000000000 > 0)
        result = result * 0x1172B83C7D517ADCDF7C8C50EB14A791F >> 128;
      if (x & 0x1000000000000000 > 0)
        result = result * 0x10B5586CF9890F6298B92B71842A98363 >> 128;
      if (x & 0x800000000000000 > 0)
        result = result * 0x1059B0D31585743AE7C548EB68CA417FD >> 128;
      if (x & 0x400000000000000 > 0)
        result = result * 0x102C9A3E778060EE6F7CACA4F7A29BDE8 >> 128;
      if (x & 0x200000000000000 > 0)
        result = result * 0x10163DA9FB33356D84A66AE336DCDFA3F >> 128;
      if (x & 0x100000000000000 > 0)
        result = result * 0x100B1AFA5ABCBED6129AB13EC11DC9543 >> 128;
      if (x & 0x80000000000000 > 0)
        result = result * 0x10058C86DA1C09EA1FF19D294CF2F679B >> 128;
      if (x & 0x40000000000000 > 0)
        result = result * 0x1002C605E2E8CEC506D21BFC89A23A00F >> 128;
      if (x & 0x20000000000000 > 0)
        result = result * 0x100162F3904051FA128BCA9C55C31E5DF >> 128;
      if (x & 0x10000000000000 > 0)
        result = result * 0x1000B175EFFDC76BA38E31671CA939725 >> 128;
      if (x & 0x8000000000000 > 0)
        result = result * 0x100058BA01FB9F96D6CACD4B180917C3D >> 128;
      if (x & 0x4000000000000 > 0)
        result = result * 0x10002C5CC37DA9491D0985C348C68E7B3 >> 128;
      if (x & 0x2000000000000 > 0)
        result = result * 0x1000162E525EE054754457D5995292026 >> 128;
      if (x & 0x1000000000000 > 0)
        result = result * 0x10000B17255775C040618BF4A4ADE83FC >> 128;
      if (x & 0x800000000000 > 0)
        result = result * 0x1000058B91B5BC9AE2EED81E9B7D4CFAB >> 128;
      if (x & 0x400000000000 > 0)
        result = result * 0x100002C5C89D5EC6CA4D7C8ACC017B7C9 >> 128;
      if (x & 0x200000000000 > 0)
        result = result * 0x10000162E43F4F831060E02D839A9D16D >> 128;
      if (x & 0x100000000000 > 0)
        result = result * 0x100000B1721BCFC99D9F890EA06911763 >> 128;
      if (x & 0x80000000000 > 0)
        result = result * 0x10000058B90CF1E6D97F9CA14DBCC1628 >> 128;
      if (x & 0x40000000000 > 0)
        result = result * 0x1000002C5C863B73F016468F6BAC5CA2B >> 128;
      if (x & 0x20000000000 > 0)
        result = result * 0x100000162E430E5A18F6119E3C02282A5 >> 128;
      if (x & 0x10000000000 > 0)
        result = result * 0x1000000B1721835514B86E6D96EFD1BFE >> 128;
      if (x & 0x8000000000 > 0)
        result = result * 0x100000058B90C0B48C6BE5DF846C5B2EF >> 128;
      if (x & 0x4000000000 > 0)
        result = result * 0x10000002C5C8601CC6B9E94213C72737A >> 128;
      if (x & 0x2000000000 > 0)
        result = result * 0x1000000162E42FFF037DF38AA2B219F06 >> 128;
      if (x & 0x1000000000 > 0)
        result = result * 0x10000000B17217FBA9C739AA5819F44F9 >> 128;
      if (x & 0x800000000 > 0)
        result = result * 0x1000000058B90BFCDEE5ACD3C1CEDC823 >> 128;
      if (x & 0x400000000 > 0)
        result = result * 0x100000002C5C85FE31F35A6A30DA1BE50 >> 128;
      if (x & 0x200000000 > 0)
        result = result * 0x10000000162E42FF0999CE3541B9FFFCF >> 128;
      if (x & 0x100000000 > 0)
        result = result * 0x100000000B17217F80F4EF5AADDA45554 >> 128;
      if (x & 0x80000000 > 0)
        result = result * 0x10000000058B90BFBF8479BD5A81B51AD >> 128;
      if (x & 0x40000000 > 0)
        result = result * 0x1000000002C5C85FDF84BD62AE30A74CC >> 128;
      if (x & 0x20000000 > 0)
        result = result * 0x100000000162E42FEFB2FED257559BDAA >> 128;
      if (x & 0x10000000 > 0)
        result = result * 0x1000000000B17217F7D5A7716BBA4A9AE >> 128;
      if (x & 0x8000000 > 0)
        result = result * 0x100000000058B90BFBE9DDBAC5E109CCE >> 128;
      if (x & 0x4000000 > 0)
        result = result * 0x10000000002C5C85FDF4B15DE6F17EB0D >> 128;
      if (x & 0x2000000 > 0)
        result = result * 0x1000000000162E42FEFA494F1478FDE05 >> 128;
      if (x & 0x1000000 > 0)
        result = result * 0x10000000000B17217F7D20CF927C8E94C >> 128;
      if (x & 0x800000 > 0)
        result = result * 0x1000000000058B90BFBE8F71CB4E4B33D >> 128;
      if (x & 0x400000 > 0)
        result = result * 0x100000000002C5C85FDF477B662B26945 >> 128;
      if (x & 0x200000 > 0)
        result = result * 0x10000000000162E42FEFA3AE53369388C >> 128;
      if (x & 0x100000 > 0)
        result = result * 0x100000000000B17217F7D1D351A389D40 >> 128;
      if (x & 0x80000 > 0)
        result = result * 0x10000000000058B90BFBE8E8B2D3D4EDE >> 128;
      if (x & 0x40000 > 0)
        result = result * 0x1000000000002C5C85FDF4741BEA6E77E >> 128;
      if (x & 0x20000 > 0)
        result = result * 0x100000000000162E42FEFA39FE95583C2 >> 128;
      if (x & 0x10000 > 0)
        result = result * 0x1000000000000B17217F7D1CFB72B45E1 >> 128;
      if (x & 0x8000 > 0)
        result = result * 0x100000000000058B90BFBE8E7CC35C3F0 >> 128;
      if (x & 0x4000 > 0)
        result = result * 0x10000000000002C5C85FDF473E242EA38 >> 128;
      if (x & 0x2000 > 0)
        result = result * 0x1000000000000162E42FEFA39F02B772C >> 128;
      if (x & 0x1000 > 0)
        result = result * 0x10000000000000B17217F7D1CF7D83C1A >> 128;
      if (x & 0x800 > 0)
        result = result * 0x1000000000000058B90BFBE8E7BDCBE2E >> 128;
      if (x & 0x400 > 0)
        result = result * 0x100000000000002C5C85FDF473DEA871F >> 128;
      if (x & 0x200 > 0)
        result = result * 0x10000000000000162E42FEFA39EF44D91 >> 128;
      if (x & 0x100 > 0)
        result = result * 0x100000000000000B17217F7D1CF79E949 >> 128;
      if (x & 0x80 > 0)
        result = result * 0x10000000000000058B90BFBE8E7BCE544 >> 128;
      if (x & 0x40 > 0)
        result = result * 0x1000000000000002C5C85FDF473DE6ECA >> 128;
      if (x & 0x20 > 0)
        result = result * 0x100000000000000162E42FEFA39EF366F >> 128;
      if (x & 0x10 > 0)
        result = result * 0x1000000000000000B17217F7D1CF79AFA >> 128;
      if (x & 0x8 > 0)
        result = result * 0x100000000000000058B90BFBE8E7BCD6D >> 128;
      if (x & 0x4 > 0)
        result = result * 0x10000000000000002C5C85FDF473DE6B2 >> 128;
      if (x & 0x2 > 0)
        result = result * 0x1000000000000000162E42FEFA39EF358 >> 128;
      if (x & 0x1 > 0)
        result = result * 0x10000000000000000B17217F7D1CF79AB >> 128;

      result >>= uint256 (int256 (63 - (x >> 64)));
      require (result <= uint256 (int256 (MAX_64x64)));

      return int128 (int256 (result));
    }
  }

  /**
   * Calculate natural exponent of x.  Revert on overflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function exp (int128 x) internal pure returns (int128) {
    unchecked {
      require (x < 0x400000000000000000); // Overflow

      if (x < -0x400000000000000000) return 0; // Underflow

      return exp_2 (
          int128 (int256 (x) * 0x171547652B82FE1777D0FFDA0D23A7D12 >> 128));
    }
  }

  /**
   * Calculate x / y rounding towards zero, where x and y are unsigned 256-bit
   * integer numbers.  Revert on overflow or when y is zero.
   *
   * @param x unsigned 256-bit integer number
   * @param y unsigned 256-bit integer number
   * @return unsigned 64.64-bit fixed point number
   */
  function divuu (uint256 x, uint256 y) private pure returns (uint128) {
    unchecked {
      require (y != 0);

      uint256 result;

      if (x <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        result = (x << 64) / y;
      else {
        uint256 msb = 192;
        uint256 xc = x >> 192;
        if (xc >= 0x100000000) { xc >>= 32; msb += 32; }
        if (xc >= 0x10000) { xc >>= 16; msb += 16; }
        if (xc >= 0x100) { xc >>= 8; msb += 8; }
        if (xc >= 0x10) { xc >>= 4; msb += 4; }
        if (xc >= 0x4) { xc >>= 2; msb += 2; }
        if (xc >= 0x2) msb += 1;  // No need to shift xc anymore

        result = (x << 255 - msb) / ((y - 1 >> msb - 191) + 1);
        require (result <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);

        uint256 hi = result * (y >> 128);
        uint256 lo = result * (y & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);

        uint256 xh = x >> 192;
        uint256 xl = x << 64;

        if (xl < lo) xh -= 1;
        xl -= lo; // We rely on overflow behavior here
        lo = hi << 128;
        if (xl < lo) xh -= 1;
        xl -= lo; // We rely on overflow behavior here

        result += xh == hi >> 128 ? xl / y : 1;
      }

      require (result <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
      return uint128 (result);
    }
  }

  /**
   * Calculate sqrt (x) rounding down, where x is unsigned 256-bit integer
   * number.
   *
   * @param x unsigned 256-bit integer number
   * @return unsigned 128-bit integer number
   */
  function sqrtu (uint256 x) private pure returns (uint128) {
    unchecked {
      if (x == 0) return 0;
      else {
        uint256 xx = x;
        uint256 r = 1;
        if (xx >= 0x100000000000000000000000000000000) { xx >>= 128; r <<= 64; }
        if (xx >= 0x10000000000000000) { xx >>= 64; r <<= 32; }
        if (xx >= 0x100000000) { xx >>= 32; r <<= 16; }
        if (xx >= 0x10000) { xx >>= 16; r <<= 8; }
        if (xx >= 0x100) { xx >>= 8; r <<= 4; }
        if (xx >= 0x10) { xx >>= 4; r <<= 2; }
        if (xx >= 0x4) { r <<= 1; }
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1; // Seven iterations should be enough
        uint256 r1 = x / r;
        return uint128 (r < r1 ? r : r1);
      }
    }
  }
}

// lib/abdk-libraries-solidity/ABDKMathQuad.sol

/*
 * ABDK Math Quad Smart Contract Library.  Copyright © 2019 by ABDK Consulting.
 * Author: Mikhail Vladimirov <mikhail.vladimirov@gmail.com>
 */

/**
 * Smart contract library of mathematical functions operating with IEEE 754
 * quadruple-precision binary floating-point numbers (quadruple precision
 * numbers).  As long as quadruple precision numbers are 16-bytes long, they are
 * represented by bytes16 type.
 */
library ABDKMathQuad {
  /*
   * 0.
   */
  bytes16 private constant POSITIVE_ZERO = 0x00000000000000000000000000000000;

  /*
   * -0.
   */
  bytes16 private constant NEGATIVE_ZERO = 0x80000000000000000000000000000000;

  /*
   * +Infinity.
   */
  bytes16 private constant POSITIVE_INFINITY = 0x7FFF0000000000000000000000000000;

  /*
   * -Infinity.
   */
  bytes16 private constant NEGATIVE_INFINITY = 0xFFFF0000000000000000000000000000;

  /*
   * Canonical NaN value.
   */
  bytes16 private constant NaN = 0x7FFF8000000000000000000000000000;

  /**
   * Convert signed 256-bit integer number into quadruple precision number.
   *
   * @param x signed 256-bit integer number
   * @return quadruple precision number
   */
  function fromInt (int256 x) internal pure returns (bytes16) {
    unchecked {
      if (x == 0) return bytes16 (0);
      else {
        // We rely on overflow behavior here
        uint256 result = uint256 (x > 0 ? x : -x);

        uint256 msb = mostSignificantBit (result);
        if (msb < 112) result <<= 112 - msb;
        else if (msb > 112) result >>= msb - 112;

        result = result & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF | 16383 + msb << 112;
        if (x < 0) result |= 0x80000000000000000000000000000000;

        return bytes16 (uint128 (result));
      }
    }
  }

  /**
   * Convert quadruple precision number into signed 256-bit integer number
   * rounding towards zero.  Revert on overflow.
   *
   * @param x quadruple precision number
   * @return signed 256-bit integer number
   */
  function toInt (bytes16 x) internal pure returns (int256) {
    unchecked {
      uint256 exponent = uint128 (x) >> 112 & 0x7FFF;

      require (exponent <= 16638); // Overflow
      if (exponent < 16383) return 0; // Underflow

      uint256 result = uint256 (uint128 (x)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF |
        0x10000000000000000000000000000;

      if (exponent < 16495) result >>= 16495 - exponent;
      else if (exponent > 16495) result <<= exponent - 16495;

      if (uint128 (x) >= 0x80000000000000000000000000000000) { // Negative
        require (result <= 0x8000000000000000000000000000000000000000000000000000000000000000);
        return -int256 (result); // We rely on overflow behavior here
      } else {
        require (result <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        return int256 (result);
      }
    }
  }

  /**
   * Convert unsigned 256-bit integer number into quadruple precision number.
   *
   * @param x unsigned 256-bit integer number
   * @return quadruple precision number
   */
  function fromUInt (uint256 x) internal pure returns (bytes16) {
    unchecked {
      if (x == 0) return bytes16 (0);
      else {
        uint256 result = x;

        uint256 msb = mostSignificantBit (result);
        if (msb < 112) result <<= 112 - msb;
        else if (msb > 112) result >>= msb - 112;

        result = result & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF | 16383 + msb << 112;

        return bytes16 (uint128 (result));
      }
    }
  }

  /**
   * Convert quadruple precision number into unsigned 256-bit integer number
   * rounding towards zero.  Revert on underflow.  Note, that negative floating
   * point numbers in range (-1.0 .. 0.0) may be converted to unsigned integer
   * without error, because they are rounded to zero.
   *
   * @param x quadruple precision number
   * @return unsigned 256-bit integer number
   */
  function toUInt (bytes16 x) internal pure returns (uint256) {
    unchecked {
      uint256 exponent = uint128 (x) >> 112 & 0x7FFF;

      if (exponent < 16383) return 0; // Underflow

      require (uint128 (x) < 0x80000000000000000000000000000000); // Negative

      require (exponent <= 16638); // Overflow
      uint256 result = uint256 (uint128 (x)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF |
        0x10000000000000000000000000000;

      if (exponent < 16495) result >>= 16495 - exponent;
      else if (exponent > 16495) result <<= exponent - 16495;

      return result;
    }
  }

  /**
   * Convert signed 128.128 bit fixed point number into quadruple precision
   * number.
   *
   * @param x signed 128.128 bit fixed point number
   * @return quadruple precision number
   */
  function from128x128 (int256 x) internal pure returns (bytes16) {
    unchecked {
      if (x == 0) return bytes16 (0);
      else {
        // We rely on overflow behavior here
        uint256 result = uint256 (x > 0 ? x : -x);

        uint256 msb = mostSignificantBit (result);
        if (msb < 112) result <<= 112 - msb;
        else if (msb > 112) result >>= msb - 112;

        result = result & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF | 16255 + msb << 112;
        if (x < 0) result |= 0x80000000000000000000000000000000;

        return bytes16 (uint128 (result));
      }
    }
  }

  /**
   * Convert quadruple precision number into signed 128.128 bit fixed point
   * number.  Revert on overflow.
   *
   * @param x quadruple precision number
   * @return signed 128.128 bit fixed point number
   */
  function to128x128 (bytes16 x) internal pure returns (int256) {
    unchecked {
      uint256 exponent = uint128 (x) >> 112 & 0x7FFF;

      require (exponent <= 16510); // Overflow
      if (exponent < 16255) return 0; // Underflow

      uint256 result = uint256 (uint128 (x)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF |
        0x10000000000000000000000000000;

      if (exponent < 16367) result >>= 16367 - exponent;
      else if (exponent > 16367) result <<= exponent - 16367;

      if (uint128 (x) >= 0x80000000000000000000000000000000) { // Negative
        require (result <= 0x8000000000000000000000000000000000000000000000000000000000000000);
        return -int256 (result); // We rely on overflow behavior here
      } else {
        require (result <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        return int256 (result);
      }
    }
  }

  /**
   * Convert signed 64.64 bit fixed point number into quadruple precision
   * number.
   *
   * @param x signed 64.64 bit fixed point number
   * @return quadruple precision number
   */
  function from64x64 (int128 x) internal pure returns (bytes16) {
    unchecked {
      if (x == 0) return bytes16 (0);
      else {
        // We rely on overflow behavior here
        uint256 result = uint128 (x > 0 ? x : -x);

        uint256 msb = mostSignificantBit (result);
        if (msb < 112) result <<= 112 - msb;
        else if (msb > 112) result >>= msb - 112;

        result = result & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF | 16319 + msb << 112;
        if (x < 0) result |= 0x80000000000000000000000000000000;

        return bytes16 (uint128 (result));
      }
    }
  }

  /**
   * Convert quadruple precision number into signed 64.64 bit fixed point
   * number.  Revert on overflow.
   *
   * @param x quadruple precision number
   * @return signed 64.64 bit fixed point number
   */
  function to64x64 (bytes16 x) internal pure returns (int128) {
    unchecked {
      uint256 exponent = uint128 (x) >> 112 & 0x7FFF;

      require (exponent <= 16446); // Overflow
      if (exponent < 16319) return 0; // Underflow

      uint256 result = uint256 (uint128 (x)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF |
        0x10000000000000000000000000000;

      if (exponent < 16431) result >>= 16431 - exponent;
      else if (exponent > 16431) result <<= exponent - 16431;

      if (uint128 (x) >= 0x80000000000000000000000000000000) { // Negative
        require (result <= 0x80000000000000000000000000000000);
        return -int128 (int256 (result)); // We rely on overflow behavior here
      } else {
        require (result <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        return int128 (int256 (result));
      }
    }
  }

  /**
   * Convert octuple precision number into quadruple precision number.
   *
   * @param x octuple precision number
   * @return quadruple precision number
   */
  function fromOctuple (bytes32 x) internal pure returns (bytes16) {
    unchecked {
      bool negative = x & 0x8000000000000000000000000000000000000000000000000000000000000000 > 0;

      uint256 exponent = uint256 (x) >> 236 & 0x7FFFF;
      uint256 significand = uint256 (x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

      if (exponent == 0x7FFFF) {
        if (significand > 0) return NaN;
        else return negative ? NEGATIVE_INFINITY : POSITIVE_INFINITY;
      }

      if (exponent > 278526)
        return negative ? NEGATIVE_INFINITY : POSITIVE_INFINITY;
      else if (exponent < 245649)
        return negative ? NEGATIVE_ZERO : POSITIVE_ZERO;
      else if (exponent < 245761) {
        significand = (significand | 0x100000000000000000000000000000000000000000000000000000000000) >> 245885 - exponent;
        exponent = 0;
      } else {
        significand >>= 124;
        exponent -= 245760;
      }

      uint128 result = uint128 (significand | exponent << 112);
      if (negative) result |= 0x80000000000000000000000000000000;

      return bytes16 (result);
    }
  }

  /**
   * Convert quadruple precision number into octuple precision number.
   *
   * @param x quadruple precision number
   * @return octuple precision number
   */
  function toOctuple (bytes16 x) internal pure returns (bytes32) {
    unchecked {
      uint256 exponent = uint128 (x) >> 112 & 0x7FFF;

      uint256 result = uint128 (x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

      if (exponent == 0x7FFF) exponent = 0x7FFFF; // Infinity or NaN
      else if (exponent == 0) {
        if (result > 0) {
          uint256 msb = mostSignificantBit (result);
          result = result << 236 - msb & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
          exponent = 245649 + msb;
        }
      } else {
        result <<= 124;
        exponent += 245760;
      }

      result |= exponent << 236;
      if (uint128 (x) >= 0x80000000000000000000000000000000)
        result |= 0x8000000000000000000000000000000000000000000000000000000000000000;

      return bytes32 (result);
    }
  }

  /**
   * Convert double precision number into quadruple precision number.
   *
   * @param x double precision number
   * @return quadruple precision number
   */
  function fromDouble (bytes8 x) internal pure returns (bytes16) {
    unchecked {
      uint256 exponent = uint64 (x) >> 52 & 0x7FF;

      uint256 result = uint64 (x) & 0xFFFFFFFFFFFFF;

      if (exponent == 0x7FF) exponent = 0x7FFF; // Infinity or NaN
      else if (exponent == 0) {
        if (result > 0) {
          uint256 msb = mostSignificantBit (result);
          result = result << 112 - msb & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
          exponent = 15309 + msb;
        }
      } else {
        result <<= 60;
        exponent += 15360;
      }

      result |= exponent << 112;
      if (x & 0x8000000000000000 > 0)
        result |= 0x80000000000000000000000000000000;

      return bytes16 (uint128 (result));
    }
  }

  /**
   * Convert quadruple precision number into double precision number.
   *
   * @param x quadruple precision number
   * @return double precision number
   */
  function toDouble (bytes16 x) internal pure returns (bytes8) {
    unchecked {
      bool negative = uint128 (x) >= 0x80000000000000000000000000000000;

      uint256 exponent = uint128 (x) >> 112 & 0x7FFF;
      uint256 significand = uint128 (x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

      if (exponent == 0x7FFF) {
        if (significand > 0) return 0x7FF8000000000000; // NaN
        else return negative ?
            bytes8 (0xFFF0000000000000) : // -Infinity
            bytes8 (0x7FF0000000000000); // Infinity
      }

      if (exponent > 17406)
        return negative ?
            bytes8 (0xFFF0000000000000) : // -Infinity
            bytes8 (0x7FF0000000000000); // Infinity
      else if (exponent < 15309)
        return negative ?
            bytes8 (0x8000000000000000) : // -0
            bytes8 (0x0000000000000000); // 0
      else if (exponent < 15361) {
        significand = (significand | 0x10000000000000000000000000000) >> 15421 - exponent;
        exponent = 0;
      } else {
        significand >>= 60;
        exponent -= 15360;
      }

      uint64 result = uint64 (significand | exponent << 52);
      if (negative) result |= 0x8000000000000000;

      return bytes8 (result);
    }
  }

  /**
   * Test whether given quadruple precision number is NaN.
   *
   * @param x quadruple precision number
   * @return true if x is NaN, false otherwise
   */
  function isNaN (bytes16 x) internal pure returns (bool) {
    unchecked {
      return uint128 (x) & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF >
        0x7FFF0000000000000000000000000000;
    }
  }

  /**
   * Test whether given quadruple precision number is positive or negative
   * infinity.
   *
   * @param x quadruple precision number
   * @return true if x is positive or negative infinity, false otherwise
   */
  function isInfinity (bytes16 x) internal pure returns (bool) {
    unchecked {
      return uint128 (x) & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF ==
        0x7FFF0000000000000000000000000000;
    }
  }

  /**
   * Calculate sign of x, i.e. -1 if x is negative, 0 if x if zero, and 1 if x
   * is positive.  Note that sign (-0) is zero.  Revert if x is NaN. 
   *
   * @param x quadruple precision number
   * @return sign of x
   */
  function sign (bytes16 x) internal pure returns (int8) {
    unchecked {
      uint128 absoluteX = uint128 (x) & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

      require (absoluteX <= 0x7FFF0000000000000000000000000000); // Not NaN

      if (absoluteX == 0) return 0;
      else if (uint128 (x) >= 0x80000000000000000000000000000000) return -1;
      else return 1;
    }
  }

  /**
   * Calculate sign (x - y).  Revert if either argument is NaN, or both
   * arguments are infinities of the same sign. 
   *
   * @param x quadruple precision number
   * @param y quadruple precision number
   * @return sign (x - y)
   */
  function cmp (bytes16 x, bytes16 y) internal pure returns (int8) {
    unchecked {
      uint128 absoluteX = uint128 (x) & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

      require (absoluteX <= 0x7FFF0000000000000000000000000000); // Not NaN

      uint128 absoluteY = uint128 (y) & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

      require (absoluteY <= 0x7FFF0000000000000000000000000000); // Not NaN

      // Not infinities of the same sign
      require (x != y || absoluteX < 0x7FFF0000000000000000000000000000);

      if (x == y) return 0;
      else {
        bool negativeX = uint128 (x) >= 0x80000000000000000000000000000000;
        bool negativeY = uint128 (y) >= 0x80000000000000000000000000000000;

        if (negativeX) {
          if (negativeY) return absoluteX > absoluteY ? -1 : int8 (1);
          else return -1; 
        } else {
          if (negativeY) return 1;
          else return absoluteX > absoluteY ? int8 (1) : -1;
        }
      }
    }
  }

  /**
   * Test whether x equals y.  NaN, infinity, and -infinity are not equal to
   * anything. 
   *
   * @param x quadruple precision number
   * @param y quadruple precision number
   * @return true if x equals to y, false otherwise
   */
  function eq (bytes16 x, bytes16 y) internal pure returns (bool) {
    unchecked {
      if (x == y) {
        return uint128 (x) & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF <
          0x7FFF0000000000000000000000000000;
      } else return false;
    }
  }

  /**
   * Calculate x + y.  Special values behave in the following way:
   *
   * NaN + x = NaN for any x.
   * Infinity + x = Infinity for any finite x.
   * -Infinity + x = -Infinity for any finite x.
   * Infinity + Infinity = Infinity.
   * -Infinity + -Infinity = -Infinity.
   * Infinity + -Infinity = -Infinity + Infinity = NaN.
   *
   * @param x quadruple precision number
   * @param y quadruple precision number
   * @return quadruple precision number
   */
  function add (bytes16 x, bytes16 y) internal pure returns (bytes16) {
    unchecked {
      uint256 xExponent = uint128 (x) >> 112 & 0x7FFF;
      uint256 yExponent = uint128 (y) >> 112 & 0x7FFF;

      if (xExponent == 0x7FFF) {
        if (yExponent == 0x7FFF) { 
          if (x == y) return x;
          else return NaN;
        } else return x; 
      } else if (yExponent == 0x7FFF) return y;
      else {
        bool xSign = uint128 (x) >= 0x80000000000000000000000000000000;
        uint256 xSignifier = uint128 (x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        if (xExponent == 0) xExponent = 1;
        else xSignifier |= 0x10000000000000000000000000000;

        bool ySign = uint128 (y) >= 0x80000000000000000000000000000000;
        uint256 ySignifier = uint128 (y) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        if (yExponent == 0) yExponent = 1;
        else ySignifier |= 0x10000000000000000000000000000;

        if (xSignifier == 0) return y == NEGATIVE_ZERO ? POSITIVE_ZERO : y;
        else if (ySignifier == 0) return x == NEGATIVE_ZERO ? POSITIVE_ZERO : x;
        else {
          int256 delta = int256 (xExponent) - int256 (yExponent);
  
          if (xSign == ySign) {
            if (delta > 112) return x;
            else if (delta > 0) ySignifier >>= uint256 (delta);
            else if (delta < -112) return y;
            else if (delta < 0) {
              xSignifier >>= uint256 (-delta);
              xExponent = yExponent;
            }
  
            xSignifier += ySignifier;
  
            if (xSignifier >= 0x20000000000000000000000000000) {
              xSignifier >>= 1;
              xExponent += 1;
            }
  
            if (xExponent == 0x7FFF)
              return xSign ? NEGATIVE_INFINITY : POSITIVE_INFINITY;
            else {
              if (xSignifier < 0x10000000000000000000000000000) xExponent = 0;
              else xSignifier &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
  
              return bytes16 (uint128 (
                  (xSign ? 0x80000000000000000000000000000000 : 0) |
                  (xExponent << 112) |
                  xSignifier)); 
            }
          } else {
            if (delta > 0) {
              xSignifier <<= 1;
              xExponent -= 1;
            } else if (delta < 0) {
              ySignifier <<= 1;
              xExponent = yExponent - 1;
            }

            if (delta > 112) ySignifier = 1;
            else if (delta > 1) ySignifier = (ySignifier - 1 >> uint256 (delta - 1)) + 1;
            else if (delta < -112) xSignifier = 1;
            else if (delta < -1) xSignifier = (xSignifier - 1 >> uint256 (-delta - 1)) + 1;

            if (xSignifier >= ySignifier) xSignifier -= ySignifier;
            else {
              xSignifier = ySignifier - xSignifier;
              xSign = ySign;
            }

            if (xSignifier == 0)
              return POSITIVE_ZERO;

            uint256 msb = mostSignificantBit (xSignifier);

            if (msb == 113) {
              xSignifier = xSignifier >> 1 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
              xExponent += 1;
            } else if (msb < 112) {
              uint256 shift = 112 - msb;
              if (xExponent > shift) {
                xSignifier = xSignifier << shift & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                xExponent -= shift;
              } else {
                xSignifier <<= xExponent - 1;
                xExponent = 0;
              }
            } else xSignifier &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

            if (xExponent == 0x7FFF)
              return xSign ? NEGATIVE_INFINITY : POSITIVE_INFINITY;
            else return bytes16 (uint128 (
                (xSign ? 0x80000000000000000000000000000000 : 0) |
                (xExponent << 112) |
                xSignifier));
          }
        }
      }
    }
  }

  /**
   * Calculate x - y.  Special values behave in the following way:
   *
   * NaN - x = NaN for any x.
   * Infinity - x = Infinity for any finite x.
   * -Infinity - x = -Infinity for any finite x.
   * Infinity - -Infinity = Infinity.
   * -Infinity - Infinity = -Infinity.
   * Infinity - Infinity = -Infinity - -Infinity = NaN.
   *
   * @param x quadruple precision number
   * @param y quadruple precision number
   * @return quadruple precision number
   */
  function sub (bytes16 x, bytes16 y) internal pure returns (bytes16) {
    unchecked {
      return add (x, y ^ 0x80000000000000000000000000000000);
    }
  }

  /**
   * Calculate x * y.  Special values behave in the following way:
   *
   * NaN * x = NaN for any x.
   * Infinity * x = Infinity for any finite positive x.
   * Infinity * x = -Infinity for any finite negative x.
   * -Infinity * x = -Infinity for any finite positive x.
   * -Infinity * x = Infinity for any finite negative x.
   * Infinity * 0 = NaN.
   * -Infinity * 0 = NaN.
   * Infinity * Infinity = Infinity.
   * Infinity * -Infinity = -Infinity.
   * -Infinity * Infinity = -Infinity.
   * -Infinity * -Infinity = Infinity.
   *
   * @param x quadruple precision number
   * @param y quadruple precision number
   * @return quadruple precision number
   */
  function mul (bytes16 x, bytes16 y) internal pure returns (bytes16) {
    unchecked {
      uint256 xExponent = uint128 (x) >> 112 & 0x7FFF;
      uint256 yExponent = uint128 (y) >> 112 & 0x7FFF;

      if (xExponent == 0x7FFF) {
        if (yExponent == 0x7FFF) {
          if (x == y) return x ^ y & 0x80000000000000000000000000000000;
          else if (x ^ y == 0x80000000000000000000000000000000) return x | y;
          else return NaN;
        } else {
          if (y & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF == 0) return NaN;
          else return x ^ y & 0x80000000000000000000000000000000;
        }
      } else if (yExponent == 0x7FFF) {
          if (x & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF == 0) return NaN;
          else return y ^ x & 0x80000000000000000000000000000000;
      } else {
        uint256 xSignifier = uint128 (x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        if (xExponent == 0) xExponent = 1;
        else xSignifier |= 0x10000000000000000000000000000;

        uint256 ySignifier = uint128 (y) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        if (yExponent == 0) yExponent = 1;
        else ySignifier |= 0x10000000000000000000000000000;

        xSignifier *= ySignifier;
        if (xSignifier == 0)
          return (x ^ y) & 0x80000000000000000000000000000000 > 0 ?
              NEGATIVE_ZERO : POSITIVE_ZERO;

        xExponent += yExponent;

        uint256 msb =
          xSignifier >= 0x200000000000000000000000000000000000000000000000000000000 ? 225 :
          xSignifier >= 0x100000000000000000000000000000000000000000000000000000000 ? 224 :
          mostSignificantBit (xSignifier);

        if (xExponent + msb < 16496) { // Underflow
          xExponent = 0;
          xSignifier = 0;
        } else if (xExponent + msb < 16608) { // Subnormal
          if (xExponent < 16496)
            xSignifier >>= 16496 - xExponent;
          else if (xExponent > 16496)
            xSignifier <<= xExponent - 16496;
          xExponent = 0;
        } else if (xExponent + msb > 49373) {
          xExponent = 0x7FFF;
          xSignifier = 0;
        } else {
          if (msb > 112)
            xSignifier >>= msb - 112;
          else if (msb < 112)
            xSignifier <<= 112 - msb;

          xSignifier &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

          xExponent = xExponent + msb - 16607;
        }

        return bytes16 (uint128 (uint128 ((x ^ y) & 0x80000000000000000000000000000000) |
            xExponent << 112 | xSignifier));
      }
    }
  }

  /**
   * Calculate x / y.  Special values behave in the following way:
   *
   * NaN / x = NaN for any x.
   * x / NaN = NaN for any x.
   * Infinity / x = Infinity for any finite non-negative x.
   * Infinity / x = -Infinity for any finite negative x including -0.
   * -Infinity / x = -Infinity for any finite non-negative x.
   * -Infinity / x = Infinity for any finite negative x including -0.
   * x / Infinity = 0 for any finite non-negative x.
   * x / -Infinity = -0 for any finite non-negative x.
   * x / Infinity = -0 for any finite non-negative x including -0.
   * x / -Infinity = 0 for any finite non-negative x including -0.
   * 
   * Infinity / Infinity = NaN.
   * Infinity / -Infinity = -NaN.
   * -Infinity / Infinity = -NaN.
   * -Infinity / -Infinity = NaN.
   *
   * Division by zero behaves in the following way:
   *
   * x / 0 = Infinity for any finite positive x.
   * x / -0 = -Infinity for any finite positive x.
   * x / 0 = -Infinity for any finite negative x.
   * x / -0 = Infinity for any finite negative x.
   * 0 / 0 = NaN.
   * 0 / -0 = NaN.
   * -0 / 0 = NaN.
   * -0 / -0 = NaN.
   *
   * @param x quadruple precision number
   * @param y quadruple precision number
   * @return quadruple precision number
   */
  function div (bytes16 x, bytes16 y) internal pure returns (bytes16) {
    unchecked {
      uint256 xExponent = uint128 (x) >> 112 & 0x7FFF;
      uint256 yExponent = uint128 (y) >> 112 & 0x7FFF;

      if (xExponent == 0x7FFF) {
        if (yExponent == 0x7FFF) return NaN;
        else return x ^ y & 0x80000000000000000000000000000000;
      } else if (yExponent == 0x7FFF) {
        if (y & 0x0000FFFFFFFFFFFFFFFFFFFFFFFFFFFF != 0) return NaN;
        else return POSITIVE_ZERO | (x ^ y) & 0x80000000000000000000000000000000;
      } else if (y & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF == 0) {
        if (x & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF == 0) return NaN;
        else return POSITIVE_INFINITY | (x ^ y) & 0x80000000000000000000000000000000;
      } else {
        uint256 ySignifier = uint128 (y) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        if (yExponent == 0) yExponent = 1;
        else ySignifier |= 0x10000000000000000000000000000;

        uint256 xSignifier = uint128 (x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        if (xExponent == 0) {
          if (xSignifier != 0) {
            uint shift = 226 - mostSignificantBit (xSignifier);

            xSignifier <<= shift;

            xExponent = 1;
            yExponent += shift - 114;
          }
        }
        else {
          xSignifier = (xSignifier | 0x10000000000000000000000000000) << 114;
        }

        xSignifier = xSignifier / ySignifier;
        if (xSignifier == 0)
          return (x ^ y) & 0x80000000000000000000000000000000 > 0 ?
              NEGATIVE_ZERO : POSITIVE_ZERO;

        assert (xSignifier >= 0x1000000000000000000000000000);

        uint256 msb =
          xSignifier >= 0x80000000000000000000000000000 ? mostSignificantBit (xSignifier) :
          xSignifier >= 0x40000000000000000000000000000 ? 114 :
          xSignifier >= 0x20000000000000000000000000000 ? 113 : 112;

        if (xExponent + msb > yExponent + 16497) { // Overflow
          xExponent = 0x7FFF;
          xSignifier = 0;
        } else if (xExponent + msb + 16380  < yExponent) { // Underflow
          xExponent = 0;
          xSignifier = 0;
        } else if (xExponent + msb + 16268  < yExponent) { // Subnormal
          if (xExponent + 16380 > yExponent)
            xSignifier <<= xExponent + 16380 - yExponent;
          else if (xExponent + 16380 < yExponent)
            xSignifier >>= yExponent - xExponent - 16380;

          xExponent = 0;
        } else { // Normal
          if (msb > 112)
            xSignifier >>= msb - 112;

          xSignifier &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

          xExponent = xExponent + msb + 16269 - yExponent;
        }

        return bytes16 (uint128 (uint128 ((x ^ y) & 0x80000000000000000000000000000000) |
            xExponent << 112 | xSignifier));
      }
    }
  }

  /**
   * Calculate -x.
   *
   * @param x quadruple precision number
   * @return quadruple precision number
   */
  function neg (bytes16 x) internal pure returns (bytes16) {
    unchecked {
      return x ^ 0x80000000000000000000000000000000;
    }
  }

  /**
   * Calculate |x|.
   *
   * @param x quadruple precision number
   * @return quadruple precision number
   */
  function abs (bytes16 x) internal pure returns (bytes16) {
    unchecked {
      return x & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    }
  }

  /**
   * Calculate square root of x.  Return NaN on negative x excluding -0.
   *
   * @param x quadruple precision number
   * @return quadruple precision number
   */
  function sqrt (bytes16 x) internal pure returns (bytes16) {
    unchecked {
      if (uint128 (x) >  0x80000000000000000000000000000000) return NaN;
      else {
        uint256 xExponent = uint128 (x) >> 112 & 0x7FFF;
        if (xExponent == 0x7FFF) return x;
        else {
          uint256 xSignifier = uint128 (x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
          if (xExponent == 0) xExponent = 1;
          else xSignifier |= 0x10000000000000000000000000000;

          if (xSignifier == 0) return POSITIVE_ZERO;

          bool oddExponent = xExponent & 0x1 == 0;
          xExponent = xExponent + 16383 >> 1;

          if (oddExponent) {
            if (xSignifier >= 0x10000000000000000000000000000)
              xSignifier <<= 113;
            else {
              uint256 msb = mostSignificantBit (xSignifier);
              uint256 shift = (226 - msb) & 0xFE;
              xSignifier <<= shift;
              xExponent -= shift - 112 >> 1;
            }
          } else {
            if (xSignifier >= 0x10000000000000000000000000000)
              xSignifier <<= 112;
            else {
              uint256 msb = mostSignificantBit (xSignifier);
              uint256 shift = (225 - msb) & 0xFE;
              xSignifier <<= shift;
              xExponent -= shift - 112 >> 1;
            }
          }

          uint256 r = 0x10000000000000000000000000000;
          r = (r + xSignifier / r) >> 1;
          r = (r + xSignifier / r) >> 1;
          r = (r + xSignifier / r) >> 1;
          r = (r + xSignifier / r) >> 1;
          r = (r + xSignifier / r) >> 1;
          r = (r + xSignifier / r) >> 1;
          r = (r + xSignifier / r) >> 1; // Seven iterations should be enough
          uint256 r1 = xSignifier / r;
          if (r1 < r) r = r1;

          return bytes16 (uint128 (xExponent << 112 | r & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
        }
      }
    }
  }

  /**
   * Calculate binary logarithm of x.  Return NaN on negative x excluding -0.
   *
   * @param x quadruple precision number
   * @return quadruple precision number
   */
  function log_2 (bytes16 x) internal pure returns (bytes16) {
    unchecked {
      if (uint128 (x) > 0x80000000000000000000000000000000) return NaN;
      else if (x == 0x3FFF0000000000000000000000000000) return POSITIVE_ZERO; 
      else {
        uint256 xExponent = uint128 (x) >> 112 & 0x7FFF;
        if (xExponent == 0x7FFF) return x;
        else {
          uint256 xSignifier = uint128 (x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
          if (xExponent == 0) xExponent = 1;
          else xSignifier |= 0x10000000000000000000000000000;

          if (xSignifier == 0) return NEGATIVE_INFINITY;

          bool resultNegative;
          uint256 resultExponent = 16495;
          uint256 resultSignifier;

          if (xExponent >= 0x3FFF) {
            resultNegative = false;
            resultSignifier = xExponent - 0x3FFF;
            xSignifier <<= 15;
          } else {
            resultNegative = true;
            if (xSignifier >= 0x10000000000000000000000000000) {
              resultSignifier = 0x3FFE - xExponent;
              xSignifier <<= 15;
            } else {
              uint256 msb = mostSignificantBit (xSignifier);
              resultSignifier = 16493 - msb;
              xSignifier <<= 127 - msb;
            }
          }

          if (xSignifier == 0x80000000000000000000000000000000) {
            if (resultNegative) resultSignifier += 1;
            uint256 shift = 112 - mostSignificantBit (resultSignifier);
            resultSignifier <<= shift;
            resultExponent -= shift;
          } else {
            uint256 bb = resultNegative ? 1 : 0;
            while (resultSignifier < 0x10000000000000000000000000000) {
              resultSignifier <<= 1;
              resultExponent -= 1;
  
              xSignifier *= xSignifier;
              uint256 b = xSignifier >> 255;
              resultSignifier += b ^ bb;
              xSignifier >>= 127 + b;
            }
          }

          return bytes16 (uint128 ((resultNegative ? 0x80000000000000000000000000000000 : 0) |
              resultExponent << 112 | resultSignifier & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
        }
      }
    }
  }

  /**
   * Calculate natural logarithm of x.  Return NaN on negative x excluding -0.
   *
   * @param x quadruple precision number
   * @return quadruple precision number
   */
  function ln (bytes16 x) internal pure returns (bytes16) {
    unchecked {
      return mul (log_2 (x), 0x3FFE62E42FEFA39EF35793C7673007E5);
    }
  }

  /**
   * Calculate 2^x.
   *
   * @param x quadruple precision number
   * @return quadruple precision number
   */
  function pow_2 (bytes16 x) internal pure returns (bytes16) {
    unchecked {
      bool xNegative = uint128 (x) > 0x80000000000000000000000000000000;
      uint256 xExponent = uint128 (x) >> 112 & 0x7FFF;
      uint256 xSignifier = uint128 (x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

      if (xExponent == 0x7FFF && xSignifier != 0) return NaN;
      else if (xExponent > 16397)
        return xNegative ? POSITIVE_ZERO : POSITIVE_INFINITY;
      else if (xExponent < 16255)
        return 0x3FFF0000000000000000000000000000;
      else {
        if (xExponent == 0) xExponent = 1;
        else xSignifier |= 0x10000000000000000000000000000;

        if (xExponent > 16367)
          xSignifier <<= xExponent - 16367;
        else if (xExponent < 16367)
          xSignifier >>= 16367 - xExponent;

        if (xNegative && xSignifier > 0x406E00000000000000000000000000000000)
          return POSITIVE_ZERO;

        if (!xNegative && xSignifier > 0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
          return POSITIVE_INFINITY;

        uint256 resultExponent = xSignifier >> 128;
        xSignifier &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        if (xNegative && xSignifier != 0) {
          xSignifier = ~xSignifier;
          resultExponent += 1;
        }

        uint256 resultSignifier = 0x80000000000000000000000000000000;
        if (xSignifier & 0x80000000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x16A09E667F3BCC908B2FB1366EA957D3E >> 128;
        if (xSignifier & 0x40000000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x1306FE0A31B7152DE8D5A46305C85EDEC >> 128;
        if (xSignifier & 0x20000000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x1172B83C7D517ADCDF7C8C50EB14A791F >> 128;
        if (xSignifier & 0x10000000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x10B5586CF9890F6298B92B71842A98363 >> 128;
        if (xSignifier & 0x8000000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x1059B0D31585743AE7C548EB68CA417FD >> 128;
        if (xSignifier & 0x4000000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x102C9A3E778060EE6F7CACA4F7A29BDE8 >> 128;
        if (xSignifier & 0x2000000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x10163DA9FB33356D84A66AE336DCDFA3F >> 128;
        if (xSignifier & 0x1000000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x100B1AFA5ABCBED6129AB13EC11DC9543 >> 128;
        if (xSignifier & 0x800000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x10058C86DA1C09EA1FF19D294CF2F679B >> 128;
        if (xSignifier & 0x400000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x1002C605E2E8CEC506D21BFC89A23A00F >> 128;
        if (xSignifier & 0x200000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x100162F3904051FA128BCA9C55C31E5DF >> 128;
        if (xSignifier & 0x100000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x1000B175EFFDC76BA38E31671CA939725 >> 128;
        if (xSignifier & 0x80000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x100058BA01FB9F96D6CACD4B180917C3D >> 128;
        if (xSignifier & 0x40000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x10002C5CC37DA9491D0985C348C68E7B3 >> 128;
        if (xSignifier & 0x20000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x1000162E525EE054754457D5995292026 >> 128;
        if (xSignifier & 0x10000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x10000B17255775C040618BF4A4ADE83FC >> 128;
        if (xSignifier & 0x8000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x1000058B91B5BC9AE2EED81E9B7D4CFAB >> 128;
        if (xSignifier & 0x4000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x100002C5C89D5EC6CA4D7C8ACC017B7C9 >> 128;
        if (xSignifier & 0x2000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x10000162E43F4F831060E02D839A9D16D >> 128;
        if (xSignifier & 0x1000000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x100000B1721BCFC99D9F890EA06911763 >> 128;
        if (xSignifier & 0x800000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x10000058B90CF1E6D97F9CA14DBCC1628 >> 128;
        if (xSignifier & 0x400000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x1000002C5C863B73F016468F6BAC5CA2B >> 128;
        if (xSignifier & 0x200000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x100000162E430E5A18F6119E3C02282A5 >> 128;
        if (xSignifier & 0x100000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x1000000B1721835514B86E6D96EFD1BFE >> 128;
        if (xSignifier & 0x80000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x100000058B90C0B48C6BE5DF846C5B2EF >> 128;
        if (xSignifier & 0x40000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x10000002C5C8601CC6B9E94213C72737A >> 128;
        if (xSignifier & 0x20000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x1000000162E42FFF037DF38AA2B219F06 >> 128;
        if (xSignifier & 0x10000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x10000000B17217FBA9C739AA5819F44F9 >> 128;
        if (xSignifier & 0x8000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x1000000058B90BFCDEE5ACD3C1CEDC823 >> 128;
        if (xSignifier & 0x4000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x100000002C5C85FE31F35A6A30DA1BE50 >> 128;
        if (xSignifier & 0x2000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x10000000162E42FF0999CE3541B9FFFCF >> 128;
        if (xSignifier & 0x1000000000000000000000000 > 0) resultSignifier = resultSignifier * 0x100000000B17217F80F4EF5AADDA45554 >> 128;
        if (xSignifier & 0x800000000000000000000000 > 0) resultSignifier = resultSignifier * 0x10000000058B90BFBF8479BD5A81B51AD >> 128;
        if (xSignifier & 0x400000000000000000000000 > 0) resultSignifier = resultSignifier * 0x1000000002C5C85FDF84BD62AE30A74CC >> 128;
        if (xSignifier & 0x200000000000000000000000 > 0) resultSignifier = resultSignifier * 0x100000000162E42FEFB2FED257559BDAA >> 128;
        if (xSignifier & 0x100000000000000000000000 > 0) resultSignifier = resultSignifier * 0x1000000000B17217F7D5A7716BBA4A9AE >> 128;
        if (xSignifier & 0x80000000000000000000000 > 0) resultSignifier = resultSignifier * 0x100000000058B90BFBE9DDBAC5E109CCE >> 128;
        if (xSignifier & 0x40000000000000000000000 > 0) resultSignifier = resultSignifier * 0x10000000002C5C85FDF4B15DE6F17EB0D >> 128;
        if (xSignifier & 0x20000000000000000000000 > 0) resultSignifier = resultSignifier * 0x1000000000162E42FEFA494F1478FDE05 >> 128;
        if (xSignifier & 0x10000000000000000000000 > 0) resultSignifier = resultSignifier * 0x10000000000B17217F7D20CF927C8E94C >> 128;
        if (xSignifier & 0x8000000000000000000000 > 0) resultSignifier = resultSignifier * 0x1000000000058B90BFBE8F71CB4E4B33D >> 128;
        if (xSignifier & 0x4000000000000000000000 > 0) resultSignifier = resultSignifier * 0x100000000002C5C85FDF477B662B26945 >> 128;
        if (xSignifier & 0x2000000000000000000000 > 0) resultSignifier = resultSignifier * 0x10000000000162E42FEFA3AE53369388C >> 128;
        if (xSignifier & 0x1000000000000000000000 > 0) resultSignifier = resultSignifier * 0x100000000000B17217F7D1D351A389D40 >> 128;
        if (xSignifier & 0x800000000000000000000 > 0) resultSignifier = resultSignifier * 0x10000000000058B90BFBE8E8B2D3D4EDE >> 128;
        if (xSignifier & 0x400000000000000000000 > 0) resultSignifier = resultSignifier * 0x1000000000002C5C85FDF4741BEA6E77E >> 128;
        if (xSignifier & 0x200000000000000000000 > 0) resultSignifier = resultSignifier * 0x100000000000162E42FEFA39FE95583C2 >> 128;
        if (xSignifier & 0x100000000000000000000 > 0) resultSignifier = resultSignifier * 0x1000000000000B17217F7D1CFB72B45E1 >> 128;
        if (xSignifier & 0x80000000000000000000 > 0) resultSignifier = resultSignifier * 0x100000000000058B90BFBE8E7CC35C3F0 >> 128;
        if (xSignifier & 0x40000000000000000000 > 0) resultSignifier = resultSignifier * 0x10000000000002C5C85FDF473E242EA38 >> 128;
        if (xSignifier & 0x20000000000000000000 > 0) resultSignifier = resultSignifier * 0x1000000000000162E42FEFA39F02B772C >> 128;
        if (xSignifier & 0x10000000000000000000 > 0) resultSignifier = resultSignifier * 0x10000000000000B17217F7D1CF7D83C1A >> 128;
        if (xSignifier & 0x8000000000000000000 > 0) resultSignifier = resultSignifier * 0x1000000000000058B90BFBE8E7BDCBE2E >> 128;
        if (xSignifier & 0x4000000000000000000 > 0) resultSignifier = resultSignifier * 0x100000000000002C5C85FDF473DEA871F >> 128;
        if (xSignifier & 0x2000000000000000000 > 0) resultSignifier = resultSignifier * 0x10000000000000162E42FEFA39EF44D91 >> 128;
        if (xSignifier & 0x1000000000000000000 > 0) resultSignifier = resultSignifier * 0x100000000000000B17217F7D1CF79E949 >> 128;
        if (xSignifier & 0x800000000000000000 > 0) resultSignifier = resultSignifier * 0x10000000000000058B90BFBE8E7BCE544 >> 128;
        if (xSignifier & 0x400000000000000000 > 0) resultSignifier = resultSignifier * 0x1000000000000002C5C85FDF473DE6ECA >> 128;
        if (xSignifier & 0x200000000000000000 > 0) resultSignifier = resultSignifier * 0x100000000000000162E42FEFA39EF366F >> 128;
        if (xSignifier & 0x100000000000000000 > 0) resultSignifier = resultSignifier * 0x1000000000000000B17217F7D1CF79AFA >> 128;
        if (xSignifier & 0x80000000000000000 > 0) resultSignifier = resultSignifier * 0x100000000000000058B90BFBE8E7BCD6D >> 128;
        if (xSignifier & 0x40000000000000000 > 0) resultSignifier = resultSignifier * 0x10000000000000002C5C85FDF473DE6B2 >> 128;
        if (xSignifier & 0x20000000000000000 > 0) resultSignifier = resultSignifier * 0x1000000000000000162E42FEFA39EF358 >> 128;
        if (xSignifier & 0x10000000000000000 > 0) resultSignifier = resultSignifier * 0x10000000000000000B17217F7D1CF79AB >> 128;
        if (xSignifier & 0x8000000000000000 > 0) resultSignifier = resultSignifier * 0x1000000000000000058B90BFBE8E7BCD5 >> 128;
        if (xSignifier & 0x4000000000000000 > 0) resultSignifier = resultSignifier * 0x100000000000000002C5C85FDF473DE6A >> 128;
        if (xSignifier & 0x2000000000000000 > 0) resultSignifier = resultSignifier * 0x10000000000000000162E42FEFA39EF34 >> 128;
        if (xSignifier & 0x1000000000000000 > 0) resultSignifier = resultSignifier * 0x100000000000000000B17217F7D1CF799 >> 128;
        if (xSignifier & 0x800000000000000 > 0) resultSignifier = resultSignifier * 0x10000000000000000058B90BFBE8E7BCC >> 128;
        if (xSignifier & 0x400000000000000 > 0) resultSignifier = resultSignifier * 0x1000000000000000002C5C85FDF473DE5 >> 128;
        if (xSignifier & 0x200000000000000 > 0) resultSignifier = resultSignifier * 0x100000000000000000162E42FEFA39EF2 >> 128;
        if (xSignifier & 0x100000000000000 > 0) resultSignifier = resultSignifier * 0x1000000000000000000B17217F7D1CF78 >> 128;
        if (xSignifier & 0x80000000000000 > 0) resultSignifier = resultSignifier * 0x100000000000000000058B90BFBE8E7BB >> 128;
        if (xSignifier & 0x40000000000000 > 0) resultSignifier = resultSignifier * 0x10000000000000000002C5C85FDF473DD >> 128;
        if (xSignifier & 0x20000000000000 > 0) resultSignifier = resultSignifier * 0x1000000000000000000162E42FEFA39EE >> 128;
        if (xSignifier & 0x10000000000000 > 0) resultSignifier = resultSignifier * 0x10000000000000000000B17217F7D1CF6 >> 128;
        if (xSignifier & 0x8000000000000 > 0) resultSignifier = resultSignifier * 0x1000000000000000000058B90BFBE8E7A >> 128;
        if (xSignifier & 0x4000000000000 > 0) resultSignifier = resultSignifier * 0x100000000000000000002C5C85FDF473C >> 128;
        if (xSignifier & 0x2000000000000 > 0) resultSignifier = resultSignifier * 0x10000000000000000000162E42FEFA39D >> 128;
        if (xSignifier & 0x1000000000000 > 0) resultSignifier = resultSignifier * 0x100000000000000000000B17217F7D1CE >> 128;
        if (xSignifier & 0x800000000000 > 0) resultSignifier = resultSignifier * 0x10000000000000000000058B90BFBE8E6 >> 128;
        if (xSignifier & 0x400000000000 > 0) resultSignifier = resultSignifier * 0x1000000000000000000002C5C85FDF472 >> 128;
        if (xSignifier & 0x200000000000 > 0) resultSignifier = resultSignifier * 0x100000000000000000000162E42FEFA38 >> 128;
        if (xSignifier & 0x100000000000 > 0) resultSignifier = resultSignifier * 0x1000000000000000000000B17217F7D1B >> 128;
        if (xSignifier & 0x80000000000 > 0) resultSignifier = resultSignifier * 0x100000000000000000000058B90BFBE8D >> 128;
        if (xSignifier & 0x40000000000 > 0) resultSignifier = resultSignifier * 0x10000000000000000000002C5C85FDF46 >> 128;
        if (xSignifier & 0x20000000000 > 0) resultSignifier = resultSignifier * 0x1000000000000000000000162E42FEFA2 >> 128;
        if (xSignifier & 0x10000000000 > 0) resultSignifier = resultSignifier * 0x10000000000000000000000B17217F7D0 >> 128;
        if (xSignifier & 0x8000000000 > 0) resultSignifier = resultSignifier * 0x1000000000000000000000058B90BFBE7 >> 128;
        if (xSignifier & 0x4000000000 > 0) resultSignifier = resultSignifier * 0x100000000000000000000002C5C85FDF3 >> 128;
        if (xSignifier & 0x2000000000 > 0) resultSignifier = resultSignifier * 0x10000000000000000000000162E42FEF9 >> 128;
        if (xSignifier & 0x1000000000 > 0) resultSignifier = resultSignifier * 0x100000000000000000000000B17217F7C >> 128;
        if (xSignifier & 0x800000000 > 0) resultSignifier = resultSignifier * 0x10000000000000000000000058B90BFBD >> 128;
        if (xSignifier & 0x400000000 > 0) resultSignifier = resultSignifier * 0x1000000000000000000000002C5C85FDE >> 128;
        if (xSignifier & 0x200000000 > 0) resultSignifier = resultSignifier * 0x100000000000000000000000162E42FEE >> 128;
        if (xSignifier & 0x100000000 > 0) resultSignifier = resultSignifier * 0x1000000000000000000000000B17217F6 >> 128;
        if (xSignifier & 0x80000000 > 0) resultSignifier = resultSignifier * 0x100000000000000000000000058B90BFA >> 128;
        if (xSignifier & 0x40000000 > 0) resultSignifier = resultSignifier * 0x10000000000000000000000002C5C85FC >> 128;
        if (xSignifier & 0x20000000 > 0) resultSignifier = resultSignifier * 0x1000000000000000000000000162E42FD >> 128;
        if (xSignifier & 0x10000000 > 0) resultSignifier = resultSignifier * 0x10000000000000000000000000B17217E >> 128;
        if (xSignifier & 0x8000000 > 0) resultSignifier = resultSignifier * 0x1000000000000000000000000058B90BE >> 128;
        if (xSignifier & 0x4000000 > 0) resultSignifier = resultSignifier * 0x100000000000000000000000002C5C85E >> 128;
        if (xSignifier & 0x2000000 > 0) resultSignifier = resultSignifier * 0x10000000000000000000000000162E42E >> 128;
        if (xSignifier & 0x1000000 > 0) resultSignifier = resultSignifier * 0x100000000000000000000000000B17216 >> 128;
        if (xSignifier & 0x800000 > 0) resultSignifier = resultSignifier * 0x10000000000000000000000000058B90A >> 128;
        if (xSignifier & 0x400000 > 0) resultSignifier = resultSignifier * 0x1000000000000000000000000002C5C84 >> 128;
        if (xSignifier & 0x200000 > 0) resultSignifier = resultSignifier * 0x100000000000000000000000000162E41 >> 128;
        if (xSignifier & 0x100000 > 0) resultSignifier = resultSignifier * 0x1000000000000000000000000000B1720 >> 128;
        if (xSignifier & 0x80000 > 0) resultSignifier = resultSignifier * 0x100000000000000000000000000058B8F >> 128;
        if (xSignifier & 0x40000 > 0) resultSignifier = resultSignifier * 0x10000000000000000000000000002C5C7 >> 128;
        if (xSignifier & 0x20000 > 0) resultSignifier = resultSignifier * 0x1000000000000000000000000000162E3 >> 128;
        if (xSignifier & 0x10000 > 0) resultSignifier = resultSignifier * 0x10000000000000000000000000000B171 >> 128;
        if (xSignifier & 0x8000 > 0) resultSignifier = resultSignifier * 0x1000000000000000000000000000058B8 >> 128;
        if (xSignifier & 0x4000 > 0) resultSignifier = resultSignifier * 0x100000000000000000000000000002C5B >> 128;
        if (xSignifier & 0x2000 > 0) resultSignifier = resultSignifier * 0x10000000000000000000000000000162D >> 128;
        if (xSignifier & 0x1000 > 0) resultSignifier = resultSignifier * 0x100000000000000000000000000000B16 >> 128;
        if (xSignifier & 0x800 > 0) resultSignifier = resultSignifier * 0x10000000000000000000000000000058A >> 128;
        if (xSignifier & 0x400 > 0) resultSignifier = resultSignifier * 0x1000000000000000000000000000002C4 >> 128;
        if (xSignifier & 0x200 > 0) resultSignifier = resultSignifier * 0x100000000000000000000000000000161 >> 128;
        if (xSignifier & 0x100 > 0) resultSignifier = resultSignifier * 0x1000000000000000000000000000000B0 >> 128;
        if (xSignifier & 0x80 > 0) resultSignifier = resultSignifier * 0x100000000000000000000000000000057 >> 128;
        if (xSignifier & 0x40 > 0) resultSignifier = resultSignifier * 0x10000000000000000000000000000002B >> 128;
        if (xSignifier & 0x20 > 0) resultSignifier = resultSignifier * 0x100000000000000000000000000000015 >> 128;
        if (xSignifier & 0x10 > 0) resultSignifier = resultSignifier * 0x10000000000000000000000000000000A >> 128;
        if (xSignifier & 0x8 > 0) resultSignifier = resultSignifier * 0x100000000000000000000000000000004 >> 128;
        if (xSignifier & 0x4 > 0) resultSignifier = resultSignifier * 0x100000000000000000000000000000001 >> 128;

        if (!xNegative) {
          resultSignifier = resultSignifier >> 15 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
          resultExponent += 0x3FFF;
        } else if (resultExponent <= 0x3FFE) {
          resultSignifier = resultSignifier >> 15 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
          resultExponent = 0x3FFF - resultExponent;
        } else {
          resultSignifier = resultSignifier >> resultExponent - 16367;
          resultExponent = 0;
        }

        return bytes16 (uint128 (resultExponent << 112 | resultSignifier));
      }
    }
  }

  /**
   * Calculate e^x.
   *
   * @param x quadruple precision number
   * @return quadruple precision number
   */
  function exp (bytes16 x) internal pure returns (bytes16) {
    unchecked {
      return pow_2 (mul (x, 0x3FFF71547652B82FE1777D0FFDA0D23A));
    }
  }

  /**
   * Get index of the most significant non-zero bit in binary representation of
   * x.  Reverts if x is zero.
   *
   * @return index of the most significant non-zero bit in binary representation
   *         of x
   */
  function mostSignificantBit (uint256 x) private pure returns (uint256) {
    unchecked {
      require (x > 0);

      uint256 result = 0;

      if (x >= 0x100000000000000000000000000000000) { x >>= 128; result += 128; }
      if (x >= 0x10000000000000000) { x >>= 64; result += 64; }
      if (x >= 0x100000000) { x >>= 32; result += 32; }
      if (x >= 0x10000) { x >>= 16; result += 16; }
      if (x >= 0x100) { x >>= 8; result += 8; }
      if (x >= 0x10) { x >>= 4; result += 4; }
      if (x >= 0x4) { x >>= 2; result += 2; }
      if (x >= 0x2) result += 1; // No need to shift x anymore

      return result;
    }
  }
}

// lib/openzeppelin-contracts/contracts/utils/Address.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/Address.sol)

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error AddressInsufficientBalance(address account);

    /**
     * @dev There's no code at `target` (it is not a contract).
     */
    error AddressEmptyCode(address target);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedInnerCall();

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert AddressInsufficientBalance(address(this));
        }

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert FailedInnerCall();
        }
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason or custom error, it is bubbled
     * up by this function (like regular Solidity function calls). However, if
     * the call reverted with no returned reason, this function reverts with a
     * {FailedInnerCall} error.
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert AddressInsufficientBalance(address(this));
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
     * was not a contract or bubbling up the revert reason (falling back to {FailedInnerCall}) in case of an
     * unsuccessful call.
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // only check if target is a contract if the call was successful and the return data is empty
            // otherwise we already know that it was a contract
            if (returndata.length == 0 && target.code.length == 0) {
                revert AddressEmptyCode(target);
            }
            return returndata;
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {FailedInnerCall} error.
     */
    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {FailedInnerCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert FailedInnerCall();
        }
    }
}

// lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol

// OpenZeppelin Contracts (last updated v5.0.0) (proxy/beacon/IBeacon.sol)

/**
 * @dev This is the interface that {BeaconProxy} expects of its beacon.
 */
interface IBeacon {
    /**
     * @dev Must return an address that can be used as a delegate call target.
     *
     * {UpgradeableBeacon} will check that this address is a contract.
     */
    function implementation() external view returns (address);
}

// lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/introspection/IERC165.sol)

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/IERC20Permit.sol)

/**
 * @dev Interface of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on {IERC20-approve}, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 *
 * ==== Security Considerations
 *
 * There are two important considerations concerning the use of `permit`. The first is that a valid permit signature
 * expresses an allowance, and it should not be assumed to convey additional meaning. In particular, it should not be
 * considered as an intention to spend the allowance in any specific way. The second is that because permits have
 * built-in replay protection and can be submitted by anyone, they can be frontrun. A protocol that uses permits should
 * take this into consideration and allow a `permit` call to fail. Combining these two aspects, a pattern that may be
 * generally recommended is:
 *
 * ```solidity
 * function doThingWithPermit(..., uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public {
 *     try token.permit(msg.sender, address(this), value, deadline, v, r, s) {} catch {}
 *     doThing(..., value);
 * }
 *
 * function doThing(..., uint256 value) public {
 *     token.safeTransferFrom(msg.sender, address(this), value);
 *     ...
 * }
 * ```
 *
 * Observe that: 1) `msg.sender` is used as the owner, leaving no ambiguity as to the signer intent, and 2) the use of
 * `try/catch` allows the permit to fail and makes the code tolerant to frontrunning. (See also
 * {SafeERC20-safeTransferFrom}).
 *
 * Additionally, note that smart contract wallets (such as Argent or Safe) are not able to produce permit signatures, so
 * contracts should have entry points that don't rely on permit.
 */
interface IERC20Permit {
    /**
     * @dev Sets `value` as the allowance of `spender` over ``owner``'s tokens,
     * given ``owner``'s signed approval.
     *
     * IMPORTANT: The same issues {IERC20-approve} has related to transaction
     * ordering also apply here.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `deadline` must be a timestamp in the future.
     * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
     * over the EIP712-formatted function arguments.
     * - the signature must use ``owner``'s current nonce (see {nonces}).
     *
     * For more information on the signature format, see the
     * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     *
     * CAUTION: See Security Considerations above.
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @dev Returns the current nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @dev Returns the domain separator used in the encoding of the signature for {permit}, as defined by {EIP712}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// src/interface/ILongStakeContract.sol

interface ILongStakeContract {
    function isStaking(string calldata machineId) external view returns (bool);
}

// src/interface/IOracle.sol

interface IOracle {
    function getTokenPriceInUSD(uint32 secondsAgo, address token) external view returns (uint256);
}

// src/interface/IPrecompileContract.sol

interface IPrecompileContract {
    function getDLCPrice() external view returns (uint256);
}

// src/interface/IRentContract.sol

interface IRentContract {
    function getTotalBurnedRentFee() external view returns (uint256);

    function getTotalRentedGPUCount() external view returns (uint256);

    function isRented(string calldata machineId) external view returns (bool);

    function getRenter(string calldata machineId) external view returns (address);

    function paidSlash(string memory machineId) external;

    function hasUnpaidSlash(string memory machineId) external view returns (bool);
}

// src/interface/IStakingContract.sol

interface IStakingContract {
    function isStaking(string calldata machineId) external view returns (bool);
    function rentMachine(string calldata machineId) external;
    function endRentMachine(string calldata machineId, uint256 baseRentFee, uint256 extraRentFee) external;
    function renewRentMachine(string memory machineId, uint256 rentFee) external;
    function reportMachineFault(string calldata machineId, address renter) external;
    function reportMachineFaultLight(string calldata machineId, address renter) external;
    function getMachineInfo(string memory machineId)
        external
        view
        returns (
            address holder,
            uint256 calcPoint,
            uint256 startAtTimestamp,
            uint256 endAtTimestamp,
            uint256 nextRenterCanRentAt,
            uint256 reservedAmount,
            bool isOnline,
            bool isRegistered
        );
    function getLeftGPUCountToStartReward() external view returns (uint256);
    function getGlobalState() external view returns (uint256, uint256, uint256);

    function getMachinesInStaking(uint256 page, uint256 pageSize) external view returns (string[] memory, uint256);

    function removeMachine(address _holder, string memory _machineId) external;

    function unStake(string calldata machineId) external;

    function stopRewarding(string memory machineId) external;
    function recoverRewarding(string memory machineId) external;
    function isStakingButOffline(string calldata machineId) external view returns (bool);
    function getRewardDuration() external view returns (uint256);
    function getMachineExtraRentFee(string memory machineId) external view returns (uint256);
    function machineIsBlocked(string memory machineId) external view returns (bool);
    function getaCalcPoint(string memory machineId) external view returns (uint256);
    function getMachineConfig(string memory machineId)
        external
        view
        returns (address[] memory beneficiaries, uint256[] memory rates, uint256 palateFormFeeRate);

    function isPersonalMachine(string memory machineId) external view returns (bool);
    function updateMachineRegisterStatus(string memory machineId,bool registered ) external;
    function endRentMachineWhenMachineOfflineAfterRentEnd(string calldata machineId) external;
}

// lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (proxy/utils/Initializable.sol)

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```solidity
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 *
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Storage of the initializable contract.
     *
     * It's implemented on a custom ERC-7201 namespace to reduce the risk of storage collisions
     * when using with upgradeable contracts.
     *
     * @custom:storage-location erc7201:openzeppelin.storage.Initializable
     */
    struct InitializableStorage {
        /**
         * @dev Indicates that the contract has been initialized.
         */
        uint64 _initialized;
        /**
         * @dev Indicates that the contract is in the process of being initialized.
         */
        bool _initializing;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant INITIALIZABLE_STORAGE = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    /**
     * @dev The contract is already initialized.
     */
    error InvalidInitialization();

    /**
     * @dev The contract is not initializing.
     */
    error NotInitializing();

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint64 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts.
     *
     * Similar to `reinitializer(1)`, except that in the context of a constructor an `initializer` may be invoked any
     * number of times. This behavior in the constructor can be useful during testing and is not expected to be used in
     * production.
     *
     * Emits an {Initialized} event.
     */
    modifier initializer() {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        // Cache values to avoid duplicated sloads
        bool isTopLevelCall = !$._initializing;
        uint64 initialized = $._initialized;

        // Allowed calls:
        // - initialSetup: the contract is not in the initializing state and no previous version was
        //                 initialized
        // - construction: the contract is initialized at version 1 (no reininitialization) and the
        //                 current contract is just being deployed
        bool initialSetup = initialized == 0 && isTopLevelCall;
        bool construction = initialized == 1 && address(this).code.length == 0;

        if (!initialSetup && !construction) {
            revert InvalidInitialization();
        }
        $._initialized = 1;
        if (isTopLevelCall) {
            $._initializing = true;
        }
        _;
        if (isTopLevelCall) {
            $._initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * A reinitializer may be used after the original initialization step. This is essential to configure modules that
     * are added through upgrades and that require initialization.
     *
     * When `version` is 1, this modifier is similar to `initializer`, except that functions marked with `reinitializer`
     * cannot be nested. If one is invoked in the context of another, execution will revert.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     *
     * WARNING: Setting the version to 2**64 - 1 will prevent any future reinitialization.
     *
     * Emits an {Initialized} event.
     */
    modifier reinitializer(uint64 version) {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing || $._initialized >= version) {
            revert InvalidInitialization();
        }
        $._initialized = version;
        $._initializing = true;
        _;
        $._initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        _checkInitializing();
        _;
    }

    /**
     * @dev Reverts if the contract is not in an initializing state. See {onlyInitializing}.
     */
    function _checkInitializing() internal view virtual {
        if (!_isInitializing()) {
            revert NotInitializing();
        }
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     *
     * Emits an {Initialized} event the first time it is successfully executed.
     */
    function _disableInitializers() internal virtual {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing) {
            revert InvalidInitialization();
        }
        if ($._initialized != type(uint64).max) {
            $._initialized = type(uint64).max;
            emit Initialized(type(uint64).max);
        }
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function _getInitializedVersion() internal view returns (uint64) {
        return _getInitializableStorage()._initialized;
    }

    /**
     * @dev Returns `true` if the contract is currently initializing. See {onlyInitializing}.
     */
    function _isInitializing() internal view returns (bool) {
        return _getInitializableStorage()._initializing;
    }

    /**
     * @dev Returns a pointer to the storage namespace.
     */
    // solhint-disable-next-line var-name-mixedcase
    function _getInitializableStorage() private pure returns (InitializableStorage storage $) {
        assembly {
            $.slot := INITIALIZABLE_STORAGE
        }
    }
}

// lib/openzeppelin-contracts/contracts/utils/math/Math.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/math/Math.sol)

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    /**
     * @dev Muldiv operation overflow.
     */
    error MathOverflowedMulDiv();

    enum Rounding {
        Floor, // Toward negative infinity
        Ceil, // Toward positive infinity
        Trunc, // Toward zero
        Expand // Away from zero
    }

    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, with an overflow flag.
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds towards infinity instead
     * of rounding towards zero.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            // Guarantee the same behavior as in a regular Solidity division.
            return a / b;
        }

        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    /**
     * @notice Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint256 or
     * denominator == 0.
     * @dev Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv) with further edits by
     * Uniswap Labs also under MIT license.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
            // use the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
            // variables such that product = prod1 * 2^256 + prod0.
            uint256 prod0 = x * y; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly {
                let mm := mulmod(x, y, not(0))
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow cases, 256 by 256 division.
            if (prod1 == 0) {
                // Solidity will revert if denominator == 0, unlike the div opcode on its own.
                // The surrounding unchecked block does not change this fact.
                // See https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic.
                return prod0 / denominator;
            }

            // Make sure the result is less than 2^256. Also prevents denominator == 0.
            if (denominator <= prod1) {
                revert MathOverflowedMulDiv();
            }

            ///////////////////////////////////////////////
            // 512 by 256 division.
            ///////////////////////////////////////////////

            // Make division exact by subtracting the remainder from [prod1 prod0].
            uint256 remainder;
            assembly {
                // Compute remainder using mulmod.
                remainder := mulmod(x, y, denominator)

                // Subtract 256 bit number from 512 bit number.
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator and compute largest power of two divisor of denominator.
            // Always >= 1. See https://cs.stackexchange.com/q/138556/92363.

            uint256 twos = denominator & (0 - denominator);
            assembly {
                // Divide denominator by twos.
                denominator := div(denominator, twos)

                // Divide [prod1 prod0] by twos.
                prod0 := div(prod0, twos)

                // Flip twos such that it is 2^256 / twos. If twos is zero, then it becomes one.
                twos := add(div(sub(0, twos), twos), 1)
            }

            // Shift in bits from prod1 into prod0.
            prod0 |= prod1 * twos;

            // Invert denominator mod 2^256. Now that denominator is an odd number, it has an inverse modulo 2^256 such
            // that denominator * inv = 1 mod 2^256. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv = 1 mod 2^4.
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also
            // works in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2^8
            inverse *= 2 - denominator * inverse; // inverse mod 2^16
            inverse *= 2 - denominator * inverse; // inverse mod 2^32
            inverse *= 2 - denominator * inverse; // inverse mod 2^64
            inverse *= 2 - denominator * inverse; // inverse mod 2^128
            inverse *= 2 - denominator * inverse; // inverse mod 2^256

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2^256. Since the preconditions guarantee that the outcome is
            // less than 2^256, this is the final result. We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inverse;
            return result;
        }
    }

    /**
     * @notice Calculates x * y / denominator with full precision, following the selected rounding direction.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, denominator);
        if (unsignedRoundsUp(rounding) && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded
     * towards zero.
     *
     * Inspired by Henry S. Warren, Jr.'s "Hacker's Delight" (Chapter 11).
     */
    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        // For our first guess, we get the biggest power of 2 which is smaller than the square root of the target.
        //
        // We know that the "msb" (most significant bit) of our target number `a` is a power of 2 such that we have
        // `msb(a) <= a < 2*msb(a)`. This value can be written `msb(a)=2**k` with `k=log2(a)`.
        //
        // This can be rewritten `2**log2(a) <= a < 2**(log2(a) + 1)`
        // → `sqrt(2**k) <= sqrt(a) < sqrt(2**(k+1))`
        // → `2**(k/2) <= sqrt(a) < 2**((k+1)/2) <= 2**(k/2 + 1)`
        //
        // Consequently, `2**(log2(a) / 2)` is a good first approximation of `sqrt(a)` with at least 1 correct bit.
        uint256 result = 1 << (log2(a) >> 1);

        // At this point `result` is an estimation with one bit of precision. We know the true value is a uint128,
        // since it is the square root of a uint256. Newton's method converges quadratically (precision doubles at
        // every iteration). We thus need at most 7 iteration to turn our partial result with one bit of precision
        // into the expected uint128 result.
        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            return min(result, a / result);
        }
    }

    /**
     * @notice Calculates sqrt(a), following the selected rounding direction.
     */
    function sqrt(uint256 a, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = sqrt(a);
            return result + (unsignedRoundsUp(rounding) && result * result < a ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 2 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log2(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 128;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 64;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 32;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 16;
            }
            if (value >> 8 > 0) {
                value >>= 8;
                result += 8;
            }
            if (value >> 4 > 0) {
                value >>= 4;
                result += 4;
            }
            if (value >> 2 > 0) {
                value >>= 2;
                result += 2;
            }
            if (value >> 1 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 2, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log2(value);
            return result + (unsignedRoundsUp(rounding) && 1 << result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 10 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return result + (unsignedRoundsUp(rounding) && 10 ** result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 256 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     *
     * Adding one to the result gives the number of pairs of hex symbols needed to represent `value` as a hex string.
     */
    function log256(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 16;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 8;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 4;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 2;
            }
            if (value >> 8 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 256, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log256(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return result + (unsignedRoundsUp(rounding) && 1 << (result << 3) < value ? 1 : 0);
        }
    }

    /**
     * @dev Returns whether a provided rounding mode is considered rounding up for unsigned integers.
     */
    function unsignedRoundsUp(Rounding rounding) internal pure returns (bool) {
        return uint8(rounding) % 2 == 1;
    }
}

// lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/StorageSlot.sol)
// This file was procedurally generated from scripts/generate/templates/StorageSlot.js.

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC1967 implementation slot:
 * ```solidity
 * contract ERC1967 {
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(newImplementation.code.length > 0);
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` with member `value` located at `slot`.
     */
    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` representation of the string storage pointer `store`.
     */
    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := store.slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` with member `value` located at `slot`.
     */
    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` representation of the bytes storage pointer `store`.
     */
    function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := store.slot
        }
    }
}

// lib/forge-std/src/console.sol

library console {
    address constant CONSOLE_ADDRESS = address(0x000000000000000000636F6e736F6c652e6c6f67);

    function _castLogPayloadViewToPure(
        function(bytes memory) internal view fnIn
    ) internal pure returns (function(bytes memory) internal pure fnOut) {
        assembly {
            fnOut := fnIn
        }
    }

    function _sendLogPayload(bytes memory payload) internal pure {
        _castLogPayloadViewToPure(_sendLogPayloadView)(payload);
    }

    function _sendLogPayloadView(bytes memory payload) private view {
        uint256 payloadLength = payload.length;
        address consoleAddress = CONSOLE_ADDRESS;
        /// @solidity memory-safe-assembly
        assembly {
            let payloadStart := add(payload, 32)
            let r := staticcall(gas(), consoleAddress, payloadStart, payloadLength, 0, 0)
        }
    }

    function log() internal pure {
        _sendLogPayload(abi.encodeWithSignature("log()"));
    }

    function logInt(int p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(int)", p0));
    }

    function logUint(uint p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint)", p0));
    }

    function logString(string memory p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string)", p0));
    }

    function logBool(bool p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool)", p0));
    }

    function logAddress(address p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address)", p0));
    }

    function logBytes(bytes memory p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes)", p0));
    }

    function logBytes1(bytes1 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes1)", p0));
    }

    function logBytes2(bytes2 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes2)", p0));
    }

    function logBytes3(bytes3 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes3)", p0));
    }

    function logBytes4(bytes4 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes4)", p0));
    }

    function logBytes5(bytes5 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes5)", p0));
    }

    function logBytes6(bytes6 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes6)", p0));
    }

    function logBytes7(bytes7 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes7)", p0));
    }

    function logBytes8(bytes8 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes8)", p0));
    }

    function logBytes9(bytes9 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes9)", p0));
    }

    function logBytes10(bytes10 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes10)", p0));
    }

    function logBytes11(bytes11 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes11)", p0));
    }

    function logBytes12(bytes12 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes12)", p0));
    }

    function logBytes13(bytes13 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes13)", p0));
    }

    function logBytes14(bytes14 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes14)", p0));
    }

    function logBytes15(bytes15 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes15)", p0));
    }

    function logBytes16(bytes16 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes16)", p0));
    }

    function logBytes17(bytes17 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes17)", p0));
    }

    function logBytes18(bytes18 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes18)", p0));
    }

    function logBytes19(bytes19 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes19)", p0));
    }

    function logBytes20(bytes20 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes20)", p0));
    }

    function logBytes21(bytes21 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes21)", p0));
    }

    function logBytes22(bytes22 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes22)", p0));
    }

    function logBytes23(bytes23 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes23)", p0));
    }

    function logBytes24(bytes24 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes24)", p0));
    }

    function logBytes25(bytes25 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes25)", p0));
    }

    function logBytes26(bytes26 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes26)", p0));
    }

    function logBytes27(bytes27 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes27)", p0));
    }

    function logBytes28(bytes28 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes28)", p0));
    }

    function logBytes29(bytes29 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes29)", p0));
    }

    function logBytes30(bytes30 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes30)", p0));
    }

    function logBytes31(bytes31 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes31)", p0));
    }

    function logBytes32(bytes32 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes32)", p0));
    }

    function log(uint p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint)", p0));
    }

    function log(int p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(int)", p0));
    }

    function log(string memory p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string)", p0));
    }

    function log(bool p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool)", p0));
    }

    function log(address p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address)", p0));
    }

    function log(uint p0, uint p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint)", p0, p1));
    }

    function log(uint p0, string memory p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string)", p0, p1));
    }

    function log(uint p0, bool p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool)", p0, p1));
    }

    function log(uint p0, address p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address)", p0, p1));
    }

    function log(string memory p0, uint p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint)", p0, p1));
    }

    function log(string memory p0, int p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,int)", p0, p1));
    }

    function log(string memory p0, string memory p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string)", p0, p1));
    }

    function log(string memory p0, bool p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool)", p0, p1));
    }

    function log(string memory p0, address p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address)", p0, p1));
    }

    function log(bool p0, uint p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint)", p0, p1));
    }

    function log(bool p0, string memory p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string)", p0, p1));
    }

    function log(bool p0, bool p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool)", p0, p1));
    }

    function log(bool p0, address p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address)", p0, p1));
    }

    function log(address p0, uint p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint)", p0, p1));
    }

    function log(address p0, string memory p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string)", p0, p1));
    }

    function log(address p0, bool p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool)", p0, p1));
    }

    function log(address p0, address p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address)", p0, p1));
    }

    function log(uint p0, uint p1, uint p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,uint)", p0, p1, p2));
    }

    function log(uint p0, uint p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,string)", p0, p1, p2));
    }

    function log(uint p0, uint p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,bool)", p0, p1, p2));
    }

    function log(uint p0, uint p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,address)", p0, p1, p2));
    }

    function log(uint p0, string memory p1, uint p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,uint)", p0, p1, p2));
    }

    function log(uint p0, string memory p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,string)", p0, p1, p2));
    }

    function log(uint p0, string memory p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,bool)", p0, p1, p2));
    }

    function log(uint p0, string memory p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,address)", p0, p1, p2));
    }

    function log(uint p0, bool p1, uint p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,uint)", p0, p1, p2));
    }

    function log(uint p0, bool p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,string)", p0, p1, p2));
    }

    function log(uint p0, bool p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,bool)", p0, p1, p2));
    }

    function log(uint p0, bool p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,address)", p0, p1, p2));
    }

    function log(uint p0, address p1, uint p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,uint)", p0, p1, p2));
    }

    function log(uint p0, address p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,string)", p0, p1, p2));
    }

    function log(uint p0, address p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,bool)", p0, p1, p2));
    }

    function log(uint p0, address p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,address)", p0, p1, p2));
    }

    function log(string memory p0, uint p1, uint p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,uint)", p0, p1, p2));
    }

    function log(string memory p0, uint p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,string)", p0, p1, p2));
    }

    function log(string memory p0, uint p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,bool)", p0, p1, p2));
    }

    function log(string memory p0, uint p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,address)", p0, p1, p2));
    }

    function log(string memory p0, string memory p1, uint p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,uint)", p0, p1, p2));
    }

    function log(string memory p0, string memory p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,string)", p0, p1, p2));
    }

    function log(string memory p0, string memory p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,bool)", p0, p1, p2));
    }

    function log(string memory p0, string memory p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,address)", p0, p1, p2));
    }

    function log(string memory p0, bool p1, uint p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,uint)", p0, p1, p2));
    }

    function log(string memory p0, bool p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,string)", p0, p1, p2));
    }

    function log(string memory p0, bool p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,bool)", p0, p1, p2));
    }

    function log(string memory p0, bool p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,address)", p0, p1, p2));
    }

    function log(string memory p0, address p1, uint p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,uint)", p0, p1, p2));
    }

    function log(string memory p0, address p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,string)", p0, p1, p2));
    }

    function log(string memory p0, address p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,bool)", p0, p1, p2));
    }

    function log(string memory p0, address p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,address)", p0, p1, p2));
    }

    function log(bool p0, uint p1, uint p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,uint)", p0, p1, p2));
    }

    function log(bool p0, uint p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,string)", p0, p1, p2));
    }

    function log(bool p0, uint p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,bool)", p0, p1, p2));
    }

    function log(bool p0, uint p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,address)", p0, p1, p2));
    }

    function log(bool p0, string memory p1, uint p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,uint)", p0, p1, p2));
    }

    function log(bool p0, string memory p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,string)", p0, p1, p2));
    }

    function log(bool p0, string memory p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,bool)", p0, p1, p2));
    }

    function log(bool p0, string memory p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,address)", p0, p1, p2));
    }

    function log(bool p0, bool p1, uint p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint)", p0, p1, p2));
    }

    function log(bool p0, bool p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,string)", p0, p1, p2));
    }

    function log(bool p0, bool p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool)", p0, p1, p2));
    }

    function log(bool p0, bool p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,address)", p0, p1, p2));
    }

    function log(bool p0, address p1, uint p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,uint)", p0, p1, p2));
    }

    function log(bool p0, address p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,string)", p0, p1, p2));
    }

    function log(bool p0, address p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,bool)", p0, p1, p2));
    }

    function log(bool p0, address p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,address)", p0, p1, p2));
    }

    function log(address p0, uint p1, uint p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,uint)", p0, p1, p2));
    }

    function log(address p0, uint p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,string)", p0, p1, p2));
    }

    function log(address p0, uint p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,bool)", p0, p1, p2));
    }

    function log(address p0, uint p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,address)", p0, p1, p2));
    }

    function log(address p0, string memory p1, uint p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,uint)", p0, p1, p2));
    }

    function log(address p0, string memory p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,string)", p0, p1, p2));
    }

    function log(address p0, string memory p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,bool)", p0, p1, p2));
    }

    function log(address p0, string memory p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,address)", p0, p1, p2));
    }

    function log(address p0, bool p1, uint p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,uint)", p0, p1, p2));
    }

    function log(address p0, bool p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,string)", p0, p1, p2));
    }

    function log(address p0, bool p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,bool)", p0, p1, p2));
    }

    function log(address p0, bool p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,address)", p0, p1, p2));
    }

    function log(address p0, address p1, uint p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,uint)", p0, p1, p2));
    }

    function log(address p0, address p1, string memory p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,string)", p0, p1, p2));
    }

    function log(address p0, address p1, bool p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,bool)", p0, p1, p2));
    }

    function log(address p0, address p1, address p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,address)", p0, p1, p2));
    }

    function log(uint p0, uint p1, uint p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,uint,uint)", p0, p1, p2, p3));
    }

    function log(uint p0, uint p1, uint p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,uint,string)", p0, p1, p2, p3));
    }

    function log(uint p0, uint p1, uint p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,uint,bool)", p0, p1, p2, p3));
    }

    function log(uint p0, uint p1, uint p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,uint,address)", p0, p1, p2, p3));
    }

    function log(uint p0, uint p1, string memory p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,string,uint)", p0, p1, p2, p3));
    }

    function log(uint p0, uint p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,string,string)", p0, p1, p2, p3));
    }

    function log(uint p0, uint p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,string,bool)", p0, p1, p2, p3));
    }

    function log(uint p0, uint p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,string,address)", p0, p1, p2, p3));
    }

    function log(uint p0, uint p1, bool p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,bool,uint)", p0, p1, p2, p3));
    }

    function log(uint p0, uint p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,bool,string)", p0, p1, p2, p3));
    }

    function log(uint p0, uint p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,bool,bool)", p0, p1, p2, p3));
    }

    function log(uint p0, uint p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,bool,address)", p0, p1, p2, p3));
    }

    function log(uint p0, uint p1, address p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,address,uint)", p0, p1, p2, p3));
    }

    function log(uint p0, uint p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,address,string)", p0, p1, p2, p3));
    }

    function log(uint p0, uint p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,address,bool)", p0, p1, p2, p3));
    }

    function log(uint p0, uint p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,address,address)", p0, p1, p2, p3));
    }

    function log(uint p0, string memory p1, uint p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,uint,uint)", p0, p1, p2, p3));
    }

    function log(uint p0, string memory p1, uint p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,uint,string)", p0, p1, p2, p3));
    }

    function log(uint p0, string memory p1, uint p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,uint,bool)", p0, p1, p2, p3));
    }

    function log(uint p0, string memory p1, uint p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,uint,address)", p0, p1, p2, p3));
    }

    function log(uint p0, string memory p1, string memory p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,string,uint)", p0, p1, p2, p3));
    }

    function log(uint p0, string memory p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,string,string)", p0, p1, p2, p3));
    }

    function log(uint p0, string memory p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,string,bool)", p0, p1, p2, p3));
    }

    function log(uint p0, string memory p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,string,address)", p0, p1, p2, p3));
    }

    function log(uint p0, string memory p1, bool p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,bool,uint)", p0, p1, p2, p3));
    }

    function log(uint p0, string memory p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,bool,string)", p0, p1, p2, p3));
    }

    function log(uint p0, string memory p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,bool,bool)", p0, p1, p2, p3));
    }

    function log(uint p0, string memory p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,bool,address)", p0, p1, p2, p3));
    }

    function log(uint p0, string memory p1, address p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,address,uint)", p0, p1, p2, p3));
    }

    function log(uint p0, string memory p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,address,string)", p0, p1, p2, p3));
    }

    function log(uint p0, string memory p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,address,bool)", p0, p1, p2, p3));
    }

    function log(uint p0, string memory p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,string,address,address)", p0, p1, p2, p3));
    }

    function log(uint p0, bool p1, uint p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,uint,uint)", p0, p1, p2, p3));
    }

    function log(uint p0, bool p1, uint p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,uint,string)", p0, p1, p2, p3));
    }

    function log(uint p0, bool p1, uint p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,uint,bool)", p0, p1, p2, p3));
    }

    function log(uint p0, bool p1, uint p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,uint,address)", p0, p1, p2, p3));
    }

    function log(uint p0, bool p1, string memory p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,string,uint)", p0, p1, p2, p3));
    }

    function log(uint p0, bool p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,string,string)", p0, p1, p2, p3));
    }

    function log(uint p0, bool p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,string,bool)", p0, p1, p2, p3));
    }

    function log(uint p0, bool p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,string,address)", p0, p1, p2, p3));
    }

    function log(uint p0, bool p1, bool p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,bool,uint)", p0, p1, p2, p3));
    }

    function log(uint p0, bool p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,bool,string)", p0, p1, p2, p3));
    }

    function log(uint p0, bool p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,bool,bool)", p0, p1, p2, p3));
    }

    function log(uint p0, bool p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,bool,address)", p0, p1, p2, p3));
    }

    function log(uint p0, bool p1, address p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,address,uint)", p0, p1, p2, p3));
    }

    function log(uint p0, bool p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,address,string)", p0, p1, p2, p3));
    }

    function log(uint p0, bool p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,address,bool)", p0, p1, p2, p3));
    }

    function log(uint p0, bool p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,bool,address,address)", p0, p1, p2, p3));
    }

    function log(uint p0, address p1, uint p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,uint,uint)", p0, p1, p2, p3));
    }

    function log(uint p0, address p1, uint p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,uint,string)", p0, p1, p2, p3));
    }

    function log(uint p0, address p1, uint p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,uint,bool)", p0, p1, p2, p3));
    }

    function log(uint p0, address p1, uint p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,uint,address)", p0, p1, p2, p3));
    }

    function log(uint p0, address p1, string memory p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,string,uint)", p0, p1, p2, p3));
    }

    function log(uint p0, address p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,string,string)", p0, p1, p2, p3));
    }

    function log(uint p0, address p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,string,bool)", p0, p1, p2, p3));
    }

    function log(uint p0, address p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,string,address)", p0, p1, p2, p3));
    }

    function log(uint p0, address p1, bool p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,bool,uint)", p0, p1, p2, p3));
    }

    function log(uint p0, address p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,bool,string)", p0, p1, p2, p3));
    }

    function log(uint p0, address p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,bool,bool)", p0, p1, p2, p3));
    }

    function log(uint p0, address p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,bool,address)", p0, p1, p2, p3));
    }

    function log(uint p0, address p1, address p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,address,uint)", p0, p1, p2, p3));
    }

    function log(uint p0, address p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,address,string)", p0, p1, p2, p3));
    }

    function log(uint p0, address p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,address,bool)", p0, p1, p2, p3));
    }

    function log(uint p0, address p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,address,address,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint p1, uint p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,uint,uint)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint p1, uint p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,uint,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint p1, uint p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,uint,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint p1, uint p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,uint,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint p1, string memory p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,string,uint)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,string,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,string,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,string,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint p1, bool p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,bool,uint)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,bool,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,bool,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,bool,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint p1, address p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,address,uint)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,address,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,address,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, uint p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,address,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, uint p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,uint,uint)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, uint p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,uint,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, uint p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,uint,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, uint p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,uint,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, string memory p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,string,uint)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,string,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,string,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,string,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, bool p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,bool,uint)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,bool,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,bool,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,bool,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, address p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,address,uint)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,address,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,address,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, string memory p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string,address,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, uint p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,uint,uint)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, uint p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,uint,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, uint p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,uint,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, uint p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,uint,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, string memory p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,string,uint)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,string,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,string,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,string,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, bool p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,uint)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, address p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,address,uint)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,address,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,address,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, bool p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool,address,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, uint p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,uint,uint)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, uint p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,uint,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, uint p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,uint,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, uint p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,uint,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, string memory p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,string,uint)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,string,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,string,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,string,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, bool p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,bool,uint)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,bool,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,bool,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,bool,address)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, address p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,address,uint)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,address,string)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,address,bool)", p0, p1, p2, p3));
    }

    function log(string memory p0, address p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address,address,address)", p0, p1, p2, p3));
    }

    function log(bool p0, uint p1, uint p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,uint,uint)", p0, p1, p2, p3));
    }

    function log(bool p0, uint p1, uint p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,uint,string)", p0, p1, p2, p3));
    }

    function log(bool p0, uint p1, uint p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,uint,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, uint p1, uint p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,uint,address)", p0, p1, p2, p3));
    }

    function log(bool p0, uint p1, string memory p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,string,uint)", p0, p1, p2, p3));
    }

    function log(bool p0, uint p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,string,string)", p0, p1, p2, p3));
    }

    function log(bool p0, uint p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,string,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, uint p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,string,address)", p0, p1, p2, p3));
    }

    function log(bool p0, uint p1, bool p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,bool,uint)", p0, p1, p2, p3));
    }

    function log(bool p0, uint p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,bool,string)", p0, p1, p2, p3));
    }

    function log(bool p0, uint p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,bool,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, uint p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,bool,address)", p0, p1, p2, p3));
    }

    function log(bool p0, uint p1, address p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,address,uint)", p0, p1, p2, p3));
    }

    function log(bool p0, uint p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,address,string)", p0, p1, p2, p3));
    }

    function log(bool p0, uint p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,address,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, uint p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,uint,address,address)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, uint p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,uint,uint)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, uint p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,uint,string)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, uint p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,uint,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, uint p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,uint,address)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, string memory p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,string,uint)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,string,string)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,string,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,string,address)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, bool p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,uint)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,string)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,address)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, address p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,address,uint)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,address,string)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,address,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, string memory p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,string,address,address)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, uint p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint,uint)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, uint p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint,string)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, uint p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, uint p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint,address)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, string memory p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,uint)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,string)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,address)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, bool p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,uint)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,string)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,address)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, address p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,uint)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,string)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, bool p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,address)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, uint p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,uint,uint)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, uint p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,uint,string)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, uint p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,uint,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, uint p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,uint,address)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, string memory p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,string,uint)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,string,string)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,string,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,string,address)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, bool p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,uint)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,string)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,address)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, address p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,address,uint)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,address,string)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,address,bool)", p0, p1, p2, p3));
    }

    function log(bool p0, address p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool,address,address,address)", p0, p1, p2, p3));
    }

    function log(address p0, uint p1, uint p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,uint,uint)", p0, p1, p2, p3));
    }

    function log(address p0, uint p1, uint p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,uint,string)", p0, p1, p2, p3));
    }

    function log(address p0, uint p1, uint p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,uint,bool)", p0, p1, p2, p3));
    }

    function log(address p0, uint p1, uint p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,uint,address)", p0, p1, p2, p3));
    }

    function log(address p0, uint p1, string memory p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,string,uint)", p0, p1, p2, p3));
    }

    function log(address p0, uint p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,string,string)", p0, p1, p2, p3));
    }

    function log(address p0, uint p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,string,bool)", p0, p1, p2, p3));
    }

    function log(address p0, uint p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,string,address)", p0, p1, p2, p3));
    }

    function log(address p0, uint p1, bool p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,bool,uint)", p0, p1, p2, p3));
    }

    function log(address p0, uint p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,bool,string)", p0, p1, p2, p3));
    }

    function log(address p0, uint p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,bool,bool)", p0, p1, p2, p3));
    }

    function log(address p0, uint p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,bool,address)", p0, p1, p2, p3));
    }

    function log(address p0, uint p1, address p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,address,uint)", p0, p1, p2, p3));
    }

    function log(address p0, uint p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,address,string)", p0, p1, p2, p3));
    }

    function log(address p0, uint p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,address,bool)", p0, p1, p2, p3));
    }

    function log(address p0, uint p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,uint,address,address)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, uint p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,uint,uint)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, uint p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,uint,string)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, uint p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,uint,bool)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, uint p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,uint,address)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, string memory p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,string,uint)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,string,string)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,string,bool)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,string,address)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, bool p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,bool,uint)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,bool,string)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,bool,bool)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,bool,address)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, address p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,address,uint)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,address,string)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,address,bool)", p0, p1, p2, p3));
    }

    function log(address p0, string memory p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,string,address,address)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, uint p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,uint,uint)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, uint p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,uint,string)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, uint p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,uint,bool)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, uint p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,uint,address)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, string memory p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,string,uint)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,string,string)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,string,bool)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,string,address)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, bool p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,uint)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,string)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,bool)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,address)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, address p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,address,uint)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,address,string)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,address,bool)", p0, p1, p2, p3));
    }

    function log(address p0, bool p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,bool,address,address)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, uint p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,uint,uint)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, uint p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,uint,string)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, uint p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,uint,bool)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, uint p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,uint,address)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, string memory p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,string,uint)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, string memory p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,string,string)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, string memory p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,string,bool)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, string memory p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,string,address)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, bool p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,bool,uint)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, bool p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,bool,string)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, bool p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,bool,bool)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, bool p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,bool,address)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, address p2, uint p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,address,uint)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, address p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,address,string)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, address p2, bool p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,address,bool)", p0, p1, p2, p3));
    }

    function log(address p0, address p1, address p2, address p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address,address,address,address)", p0, p1, p2, p3));
    }
}

// lib/openzeppelin-contracts/contracts/interfaces/draft-IERC1822.sol

// OpenZeppelin Contracts (last updated v5.0.0) (interfaces/draft-IERC1822.sol)

/**
 * @dev ERC1822: Universal Upgradeable Proxy Standard (UUPS) documents a method for upgradeability through a simplified
 * proxy whose upgrades are fully controlled by the current implementation.
 */
interface IERC1822Proxiable {
    /**
     * @dev Returns the storage slot that the proxiable contract assumes is being used to store the implementation
     * address.
     *
     * IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this risks
     * bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that this
     * function revert if invoked through a proxy.
     */
    function proxiableUUID() external view returns (bytes32);
}

// lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol

// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol

// OpenZeppelin Contracts (last updated v5.0.1) (token/ERC1155/IERC1155.sol)

/**
 * @dev Required interface of an ERC1155 compliant contract, as defined in the
 * https://eips.ethereum.org/EIPS/eip-1155[EIP].
 */
interface IERC1155 is IERC165 {
    /**
     * @dev Emitted when `value` amount of tokens of type `id` are transferred from `from` to `to` by `operator`.
     */
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    /**
     * @dev Equivalent to multiple {TransferSingle} events, where `operator`, `from` and `to` are the same for all
     * transfers.
     */
    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );

    /**
     * @dev Emitted when `account` grants or revokes permission to `operator` to transfer their tokens, according to
     * `approved`.
     */
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);

    /**
     * @dev Emitted when the URI for token type `id` changes to `value`, if it is a non-programmatic URI.
     *
     * If an {URI} event was emitted for `id`, the standard
     * https://eips.ethereum.org/EIPS/eip-1155#metadata-extensions[guarantees] that `value` will equal the value
     * returned by {IERC1155MetadataURI-uri}.
     */
    event URI(string value, uint256 indexed id);

    /**
     * @dev Returns the value of tokens of token type `id` owned by `account`.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id) external view returns (uint256);

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {balanceOf}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(
        address[] calldata accounts,
        uint256[] calldata ids
    ) external view returns (uint256[] memory);

    /**
     * @dev Grants or revokes permission to `operator` to transfer the caller's tokens, according to `approved`,
     *
     * Emits an {ApprovalForAll} event.
     *
     * Requirements:
     *
     * - `operator` cannot be the caller.
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @dev Returns true if `operator` is approved to transfer ``account``'s tokens.
     *
     * See {setApprovalForAll}.
     */
    function isApprovedForAll(address account, address operator) external view returns (bool);

    /**
     * @dev Transfers a `value` amount of tokens of type `id` from `from` to `to`.
     *
     * WARNING: This function can potentially allow a reentrancy attack when transferring tokens
     * to an untrusted contract, when invoking {onERC1155Received} on the receiver.
     * Ensure to follow the checks-effects-interactions pattern and consider employing
     * reentrancy guards when interacting with untrusted contracts.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - If the caller is not `from`, it must have been approved to spend ``from``'s tokens via {setApprovalForAll}.
     * - `from` must have a balance of tokens of type `id` of at least `value` amount.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) external;

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {safeTransferFrom}.
     *
     * WARNING: This function can potentially allow a reentrancy attack when transferring tokens
     * to an untrusted contract, when invoking {onERC1155BatchReceived} on the receiver.
     * Ensure to follow the checks-effects-interactions pattern and consider employing
     * reentrancy guards when interacting with untrusted contracts.
     *
     * Emits either a {TransferSingle} or a {TransferBatch} event, depending on the length of the array arguments.
     *
     * Requirements:
     *
     * - `ids` and `values` must have the same length.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external;
}

// lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC1155/IERC1155Receiver.sol)

/**
 * @dev Interface that must be implemented by smart contracts in order to receive
 * ERC-1155 token transfers.
 */
interface IERC1155Receiver is IERC165 {
    /**
     * @dev Handles the receipt of a single ERC1155 token type. This function is
     * called at the end of a `safeTransferFrom` after the balance has been updated.
     *
     * NOTE: To accept the transfer, this must return
     * `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
     * (i.e. 0xf23a6e61, or its own function selector).
     *
     * @param operator The address which initiated the transfer (i.e. msg.sender)
     * @param from The address which previously owned the token
     * @param id The ID of the token being transferred
     * @param value The amount of tokens being transferred
     * @param data Additional data with no specified format
     * @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
     */
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4);

    /**
     * @dev Handles the receipt of a multiple ERC1155 token types. This function
     * is called at the end of a `safeBatchTransferFrom` after the balances have
     * been updated.
     *
     * NOTE: To accept the transfer(s), this must return
     * `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
     * (i.e. 0xbc197c81, or its own function selector).
     *
     * @param operator The address which initiated the batch transfer (i.e. msg.sender)
     * @param from The address which previously owned the token
     * @param ids An array containing ids of each token being transferred (order and length must match values array)
     * @param values An array containing amounts of each token being transferred (order and length must match ids array)
     * @param data Additional data with no specified format
     * @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` if transfer is allowed
     */
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4);
}

// src/interface/IRewardToken.sol

interface IRewardToken is IERC20 {
    function burnFrom(address account, uint256 value) external;
}

// src/NFTStakingState.sol

/// @custom:oz-upgrades-from OldNFTStakingState
contract NFTStakingState {
    IRentContract public rentContract;

    uint256 public totalReservedAmount;
    uint256 public totalGpuCount;
    uint256 public totalCalcPoint;
    uint256 public addressCountInStaking;
    string[] public machineIds;
    SimpleStakeHolder[] public topStakeHolders;

    mapping(address => uint8) public address2MachineCount;
    mapping(address => StakeHolderInfo) public stakeHolders;

    struct StateSummary {
        uint256 totalCalcPoint;
        uint256 totalGPUCount;
        uint256 totalCalcPointPoolCount;
        uint256 totalRentedGPUCount;
        uint256 totalBurnedRentFee;
        uint256 totalReservedAmount;
    }

    struct MachineInfo {
        uint256 calcPoint;
        uint8 gpuCount;
        uint256 reserveAmount;
        uint256 burnedRentFee;
        uint8 rentedGPUCount;
        uint256 totalClaimedRewardAmount;
        uint256 releasedRewardAmount;
    }

    struct StakeHolderInfo {
        address holder;
        uint256 totalCalcPoint;
        uint256 totalGPUCount;
        uint256 rentedGPUCount;
        uint256 totalReservedAmount;
        uint256 burnedRentFee;
        uint256 totalClaimedRewardAmount;
        uint256 releasedRewardAmount;
        string[] machineIds;
        mapping(string => MachineInfo) machineId2Info;
    }

    struct SimpleStakeHolder {
        address holder;
        uint256 totalCalcPoint;
    }

    struct StakeHolder {
        address holder;
        uint256 totalCalcPoint;
        uint256 totalGPUCount;
        uint256 rentedGPUCount;
        uint256 totalReservedAmount;
        uint256 burnedRentFee;
        uint256 totalClaimedRewardAmount;
        uint256 releasedRewardAmount;
    }

    modifier onlyRentAddress() {
        require(msg.sender == address(rentContract), "Only RentContractAddress can call this function");
        _;
    }

    function __State_Init(address _rentContract) internal {
        rentContract = IRentContract(_rentContract);
    }

    //
    //    function findStringIndex(string[] memory arr, string memory v) internal pure returns (uint256, bool) {
    //        for (uint256 i = 0; i < arr.length; i++) {
    //            if (keccak256(abi.encodePacked(arr[i])) == keccak256(abi.encodePacked(v))) {
    //                return (i, true);
    //            }
    //        }
    //        return (0, false);
    //    }
    //
    //    function removeStringValueOfArray(string memory addr, string[] storage arr) internal {
    //        (uint256 index, bool found) = findStringIndex(arr, addr);
    //        if (!found) {
    //            return;
    //        }
    //        arr[index] = arr[arr.length - 1];
    //        arr.pop();
    //    }

    //    function setBurnedRentFee(address _holder, string memory _machineId, uint256 fee) external onlyRentAddress {
    //        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];
    //
    //        if (stakeHolderInfo.holder == address(0)) {
    //            stakeHolderInfo.holder = _holder;
    //        }
    //
    //        MachineInfo storage previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];
    //        previousMachineInfo.burnedRentFee += fee;
    //        stakeHolderInfo.burnedRentFee += fee;
    //    }

    //    function addRentedGPUCount(address _holder, string memory _machineId) external onlyRentAddress {
    //        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];
    //
    //        if (stakeHolderInfo.holder == address(0)) {
    //            stakeHolderInfo.holder = _holder;
    //        }
    //
    //        MachineInfo storage previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];
    //        previousMachineInfo.rentedGPUCount += 1;
    //        stakeHolderInfo.rentedGPUCount += 1;
    //    }

    //    function subRentedGPUCount(address _holder, string memory _machineId) internal {
    //        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];
    //
    //        if (stakeHolderInfo.holder == address(0)) {
    //            stakeHolderInfo.holder = _holder;
    //        }
    //
    //        MachineInfo storage previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];
    //        if (previousMachineInfo.rentedGPUCount >= 1) {
    //            previousMachineInfo.rentedGPUCount -= 1;
    //            stakeHolderInfo.rentedGPUCount -= 1;
    //        }
    //    }

    //    function addReserveAmount(string memory _machineId, address _holder, uint256 _reserveAmount) internal {
    //        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];
    //
    //        if (stakeHolderInfo.holder == address(0)) {
    //            stakeHolderInfo.holder = _holder;
    //        }
    //
    //        MachineInfo storage previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];
    //
    //        previousMachineInfo.reserveAmount += _reserveAmount;
    //        stakeHolderInfo.totalReservedAmount += _reserveAmount;
    //    }

    //    function subReserveAmount(address _holder, string memory _machineId, uint256 _reserveAmount) internal {
    //        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];
    //
    //        if (stakeHolderInfo.holder == address(0)) {
    //            stakeHolderInfo.holder = _holder;
    //        }
    //
    //        MachineInfo storage previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];
    //
    //        if (previousMachineInfo.reserveAmount > _reserveAmount) {
    //            previousMachineInfo.reserveAmount -= _reserveAmount;
    //        } else {
    //            previousMachineInfo.reserveAmount = 0;
    //        }
    //
    //        if (stakeHolderInfo.totalReservedAmount > _reserveAmount) {
    //            stakeHolderInfo.totalReservedAmount -= _reserveAmount;
    //        } else {
    //            stakeHolderInfo.totalReservedAmount = 0;
    //        }
    //    }

    //    function addClaimedRewardAmount(
    //        address _holder,
    //        string memory _machineId,
    //        uint256 totalClaimedAmount,
    //        uint256 releasedAmount
    //    ) internal {
    //        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];
    //
    //        if (stakeHolderInfo.holder == address(0)) {
    //            stakeHolderInfo.holder = _holder;
    //        }
    //
    //        MachineInfo storage previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];
    //
    //        previousMachineInfo.totalClaimedRewardAmount += totalClaimedAmount;
    //        previousMachineInfo.releasedRewardAmount += releasedAmount;
    //        stakeHolderInfo.totalClaimedRewardAmount += totalClaimedAmount;
    //        stakeHolderInfo.releasedRewardAmount += releasedAmount;
    //    }

    //    function addOrUpdateStakeHolder(
    //        address _holder,
    //        string memory _machineId,
    //        uint256 _calcPoint,
    //        uint8 _gpuCount,
    //        bool isAdd
    //    ) internal {
    //        require(_holder != address(0), "Invalid holder address");
    //        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];
    //
    //        if (stakeHolderInfo.holder == address(0)) {
    //            stakeHolderInfo.holder = _holder;
    //        }
    //
    //        if (isAdd) {
    //            machineIds.push(_machineId);
    //            uint256 stakedMachineCount = address2MachineCount[_holder];
    //            if (stakedMachineCount == 0) {
    //                addressCountInStaking += 1;
    //            }
    //            address2MachineCount[_holder] += 1;
    //
    //            stakeHolderInfo.totalGPUCount += _gpuCount;
    //            stakeHolderInfo.machineId2Info[_machineId].gpuCount = _gpuCount;
    //        }
    //
    //        MachineInfo memory previousMachineInfo = stakeHolderInfo.machineId2Info[_machineId];
    //        stakeHolderInfo.machineId2Info[_machineId].calcPoint = _calcPoint;
    //
    //        if (previousMachineInfo.calcPoint == 0) {
    //            stakeHolderInfo.machineIds.push(_machineId);
    //        }
    //
    //        stakeHolderInfo.totalCalcPoint = stakeHolderInfo.totalCalcPoint + _calcPoint - previousMachineInfo.calcPoint;
    //
    ////        updateTopStakeHolders(_holder, stakeHolderInfo.totalCalcPoint);
    //    }

    //    function removeMachine(address _holder, string memory _machineId) internal {
    //        StakeHolderInfo storage stakeHolderInfo = stakeHolders[_holder];
    //
    //        MachineInfo memory stakeInfoToRemove = stakeHolderInfo.machineId2Info[_machineId];
    //        if (stakeInfoToRemove.calcPoint > 0) {
    //            stakeHolderInfo.totalCalcPoint -= stakeInfoToRemove.calcPoint;
    //        }
    //
    //        stakeHolderInfo.totalGPUCount -= stakeInfoToRemove.gpuCount;
    //        stakeHolderInfo.totalReservedAmount -= stakeInfoToRemove.reserveAmount;
    //        stakeHolderInfo.rentedGPUCount -= stakeInfoToRemove.rentedGPUCount;
    //        removeStringValueOfArray(_machineId, stakeHolderInfo.machineIds);
    //        delete stakeHolderInfo.machineId2Info[_machineId];
    //        removeMachineIdByValueUnordered(_machineId);
    //
    //        uint256 stakedMachineCount = address2MachineCount[_holder];
    //        if (stakedMachineCount > 0) {
    //            if (stakedMachineCount == 1) {
    //                addressCountInStaking -= 1;
    //            }
    //            if (address2MachineCount[_holder] > 0) {
    //                address2MachineCount[_holder] -= 1;
    //            }
    //        }
    //
    //        updateTopStakeHolders(_holder, stakeHolderInfo.totalCalcPoint);
    //    }

    //    function updateTopStakeHolders(address _holder, uint256 newCalcPoint) internal {
    //        bool exists = false;
    //        uint256 index;
    //
    //        for (uint256 i = 0; i < topStakeHolders.length; i++) {
    //            if (topStakeHolders[i].holder == _holder) {
    //                exists = true;
    //                index = i;
    //                break;
    //            }
    //        }
    //
    //        if (exists) {
    //            topStakeHolders[index].totalCalcPoint = newCalcPoint;
    //        } else {
    //            topStakeHolders.push(SimpleStakeHolder(_holder, newCalcPoint));
    //            index = topStakeHolders.length - 1;
    //        }
    //    }

    //    function getHolderMachineIds(address _holder) external view returns (string[] memory) {
    //        return stakeHolders[_holder].machineIds;
    //    }
    //
    //    function getTopStakeHolders(uint256 offset, uint256 limit)
    //        external
    //        view
    //        returns (StakeHolder[] memory, uint256 total)
    //    {
    //        uint256 totalItems = topStakeHolders.length;
    //
    //        if (offset >= totalItems) {
    //            StakeHolder[] memory empty = new StakeHolder[](0);
    //            return (empty, totalItems);
    //        }
    //
    //        uint256 end = offset + limit;
    //        if (end > totalItems) {
    //            end = totalItems;
    //        }
    //
    //        uint256 size = end - offset;
    //
    //        SimpleStakeHolder[] memory sortedStakeHolders = new SimpleStakeHolder[](totalItems);
    //
    //        for (uint256 i = 0; i < totalItems; i++) {
    //            sortedStakeHolders[i] = topStakeHolders[i];
    //        }
    //
    //        selectionSort(sortedStakeHolders);
    //
    //        StakeHolder[] memory result = new StakeHolder[](size);
    //
    //        for (uint256 i = 0; i < size; i++) {
    //            SimpleStakeHolder memory simpleHolder = sortedStakeHolders[offset + i];
    //            StakeHolderInfo storage stakeHolderInfo = stakeHolders[simpleHolder.holder];
    //
    //            result[i] = StakeHolder({
    //                holder: simpleHolder.holder,
    //                totalCalcPoint: simpleHolder.totalCalcPoint,
    //                totalGPUCount: stakeHolderInfo.totalGPUCount,
    //                totalReservedAmount: stakeHolderInfo.totalReservedAmount,
    //                rentedGPUCount: stakeHolderInfo.rentedGPUCount,
    //                burnedRentFee: stakeHolderInfo.burnedRentFee,
    //                totalClaimedRewardAmount: stakeHolderInfo.totalClaimedRewardAmount,
    //                releasedRewardAmount: stakeHolderInfo.releasedRewardAmount
    //            });
    //        }
    //
    //        return (result, totalItems);
    //    }

    //    function selectionSort(SimpleStakeHolder[] memory arr) internal pure {
    //        uint256 len = arr.length;
    //        for (uint256 i = 0; i < len - 1; i++) {
    //            uint256 maxIndex = i;
    //            for (uint256 j = i + 1; j < len; j++) {
    //                if (arr[j].totalCalcPoint > arr[maxIndex].totalCalcPoint) {
    //                    maxIndex = j;
    //                }
    //            }
    //            if (maxIndex != i) {
    //                SimpleStakeHolder memory temp = arr[i];
    //                arr[i] = arr[maxIndex];
    //                arr[maxIndex] = temp;
    //            }
    //        }
    //    }

    //    function removeMachineIdByValueUnordered(string memory machineId) internal {
    //        (uint256 index, bool found) = findMachineIdIndex(machineId);
    //        if (!found) {
    //            return;
    //        }
    //        machineIds[index] = machineIds[machineIds.length - 1];
    //
    //        machineIds.pop();
    //    }

    //    function findMachineIdIndex(string memory machineId) internal view returns (uint256, bool) {
    //        for (uint256 i = 0; i < machineIds.length; i++) {
    //            if (keccak256(abi.encodePacked(machineIds[i])) == keccak256(abi.encodePacked(machineId))) {
    //                return (i, true);
    //            }
    //        }
    //        return (0, false);
    //    }

    //    function getMachinesInStaking(uint256 startIndex, uint256 pageSize)
    //        external
    //        view
    //        returns (string[] memory, uint256)
    //    {
    //        if (startIndex > machineIds.length) {
    //            return (new string[](0), machineIds.length);
    //        }
    //
    //        uint256 endIndex = startIndex + pageSize;
    //        if (endIndex > machineIds.length) {
    //            endIndex = machineIds.length;
    //        }
    //        uint256 length = endIndex - startIndex;
    //
    //        string[] memory pageItems = new string[](length);
    //        for (uint256 i = 0; i < length; i++) {
    //            pageItems[i] = machineIds[startIndex + i];
    //        }
    //
    //        return (pageItems, machineIds.length);
    //    }

    //    function getRentedGPUCountInDlcNftStaking() external view returns (uint256) {
    //        return rentContract.getTotalRentedGPUCount();
    //    }

    //    function getTotalDlcNftStakingBurnedRentFee() external view returns (uint256) {
    //        return rentContract.getTotalBurnedRentFee();
    //    }

    //    function getStateSummary() public view returns (StateSummary memory) {
    //        return StateSummary({
    //            totalCalcPoint: totalCalcPoint,
    //            totalGPUCount: totalGpuCount,
    //            totalCalcPointPoolCount: addressCountInStaking,
    //            totalRentedGPUCount: rentContract.getTotalRentedGPUCount(),
    //            totalBurnedRentFee: rentContract.getTotalBurnedRentFee(),
    //            totalReservedAmount: totalReservedAmount
    //        });
    //    }

    //    function isRented(string calldata machineId) external view returns (bool) {
    //        return rentContract.isRented(machineId);
    //    }
}

// lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/ReentrancyGuard.sol)

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuardUpgradeable is Initializable {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    /// @custom:storage-location erc7201:openzeppelin.storage.ReentrancyGuard
    struct ReentrancyGuardStorage {
        uint256 _status;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ReentrancyGuardStorageLocation = 0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    function _getReentrancyGuardStorage() private pure returns (ReentrancyGuardStorage storage $) {
        assembly {
            $.slot := ReentrancyGuardStorageLocation
        }
    }

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    function __ReentrancyGuard_init() internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal onlyInitializing {
        ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
        $._status = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if ($._status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        $._status = ENTERED;
    }

    function _nonReentrantAfter() private {
        ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        $._status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
        return $._status == ENTERED;
    }
}

// lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    /// @custom:storage-location erc7201:openzeppelin.storage.Ownable
    struct OwnableStorage {
        address _owner;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Ownable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OwnableStorageLocation = 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;

    function _getOwnableStorage() private pure returns (OwnableStorage storage $) {
        assembly {
            $.slot := OwnableStorageLocation
        }
    }

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    function __Ownable_init(address initialOwner) internal onlyInitializing {
        __Ownable_init_unchained(initialOwner);
    }

    function __Ownable_init_unchained(address initialOwner) internal onlyInitializing {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        OwnableStorage storage $ = _getOwnableStorage();
        return $._owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        OwnableStorage storage $ = _getOwnableStorage();
        address oldOwner = $._owner;
        $._owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// src/library/RewardCalculatorLib.sol

library RewardCalculatorLib {
    uint256 private constant PRECISION_FACTOR = 1 ether;

    struct RewardsPerShare {
        uint256 accumulatedPerShare; // accumulated rewards per share
        uint256 lastUpdated; // accumulated rewards per share last updated time
    }

    struct UserRewards {
        uint256 accumulated; // user accumulated rewards
        uint256 lastAccumulatedPerShare; // last accumulated rewards per share of user
    }

    function getUpdateRewardsPerShare(
        RewardsPerShare memory rewardsPerShareIn,
        uint256 totalShares,
        uint256 rewardsRate,
        uint256 rewardsStart,
        uint256 rewardsEnd
    ) internal view returns (RewardsPerShare memory) {
        RewardsPerShare memory rewardsPerTokenOut =
            RewardsPerShare(rewardsPerShareIn.accumulatedPerShare, rewardsPerShareIn.lastUpdated);

        if (block.timestamp < rewardsStart) return rewardsPerTokenOut;

        uint256 updateTime = block.timestamp < rewardsEnd ? block.timestamp : rewardsEnd;
        uint256 elapsed = updateTime > rewardsPerShareIn.lastUpdated ? updateTime - rewardsPerShareIn.lastUpdated : 0;

        if (elapsed == 0) return rewardsPerTokenOut;
        rewardsPerTokenOut.lastUpdated = updateTime;

        if (totalShares == 0) return rewardsPerTokenOut;

        rewardsPerTokenOut.accumulatedPerShare =
            rewardsPerShareIn.accumulatedPerShare + PRECISION_FACTOR * elapsed * rewardsRate / totalShares;

        return rewardsPerTokenOut;
    }

    function getUpdateUserRewards(
        UserRewards memory userRewardsIn,
        uint256 userShares,
        RewardsPerShare memory rewardsPerToken_
    ) internal pure returns (UserRewards memory) {
        if (userRewardsIn.lastAccumulatedPerShare == rewardsPerToken_.lastUpdated) return userRewardsIn;

        UserRewards memory userRewardsOut = UserRewards(userRewardsIn.accumulated, rewardsPerToken_.accumulatedPerShare);
        userRewardsOut.accumulated = calculatePendingUserRewards(
            userShares, userRewardsIn.lastAccumulatedPerShare, rewardsPerToken_.accumulatedPerShare
        ) + userRewardsIn.accumulated;
        userRewardsOut.lastAccumulatedPerShare = rewardsPerToken_.accumulatedPerShare;

        return userRewardsOut;
    }

    function calculatePendingUserRewards(
        uint256 userShares,
        uint256 earlierAccumulatedPerShare,
        uint256 latterAccumulatedPerShare
    ) internal pure returns (uint256) {
        return userShares * (latterAccumulatedPerShare - earlierAccumulatedPerShare) / PRECISION_FACTOR;
    }
}

// lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol

// OpenZeppelin Contracts (last updated v5.0.0) (proxy/ERC1967/ERC1967Utils.sol)

/**
 * @dev This abstract contract provides getters and event emitting update functions for
 * https://eips.ethereum.org/EIPS/eip-1967[EIP1967] slots.
 */
library ERC1967Utils {
    // We re-declare ERC-1967 events here because they can't be used directly from IERC1967.
    // This will be fixed in Solidity 0.8.21. At that point we should remove these events.
    /**
     * @dev Emitted when the implementation is upgraded.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Emitted when the beacon is changed.
     */
    event BeaconUpgraded(address indexed beacon);

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev The `implementation` of the proxy is invalid.
     */
    error ERC1967InvalidImplementation(address implementation);

    /**
     * @dev The `admin` of the proxy is invalid.
     */
    error ERC1967InvalidAdmin(address admin);

    /**
     * @dev The `beacon` of the proxy is invalid.
     */
    error ERC1967InvalidBeacon(address beacon);

    /**
     * @dev An upgrade function sees `msg.value > 0` that may be lost.
     */
    error ERC1967NonPayable();

    /**
     * @dev Returns the current implementation address.
     */
    function getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 implementation slot.
     */
    function _setImplementation(address newImplementation) private {
        if (newImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(newImplementation);
        }
        StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
     * @dev Performs implementation upgrade with additional setup call if data is nonempty.
     * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
     * to avoid stuck value in the contract.
     *
     * Emits an {IERC1967-Upgraded} event.
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);

        if (data.length > 0) {
            Address.functionDelegateCall(newImplementation, data);
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Returns the current admin.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using
     * the https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
     */
    function getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(ADMIN_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert ERC1967InvalidAdmin(address(0));
        }
        StorageSlot.getAddressSlot(ADMIN_SLOT).value = newAdmin;
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {IERC1967-AdminChanged} event.
     */
    function changeAdmin(address newAdmin) internal {
        emit AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev The storage slot of the UpgradeableBeacon contract which defines the implementation for this proxy.
     * This is the keccak-256 hash of "eip1967.proxy.beacon" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /**
     * @dev Returns the current beacon.
     */
    function getBeacon() internal view returns (address) {
        return StorageSlot.getAddressSlot(BEACON_SLOT).value;
    }

    /**
     * @dev Stores a new beacon in the EIP1967 beacon slot.
     */
    function _setBeacon(address newBeacon) private {
        if (newBeacon.code.length == 0) {
            revert ERC1967InvalidBeacon(newBeacon);
        }

        StorageSlot.getAddressSlot(BEACON_SLOT).value = newBeacon;

        address beaconImplementation = IBeacon(newBeacon).implementation();
        if (beaconImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(beaconImplementation);
        }
    }

    /**
     * @dev Change the beacon and trigger a setup call if data is nonempty.
     * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
     * to avoid stuck value in the contract.
     *
     * Emits an {IERC1967-BeaconUpgraded} event.
     *
     * CAUTION: Invoking this function has no effect on an instance of {BeaconProxy} since v5, since
     * it uses an immutable beacon without looking at the value of the ERC-1967 beacon slot for
     * efficiency.
     */
    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            Address.functionDelegateCall(IBeacon(newBeacon).implementation(), data);
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Reverts if `msg.value` is not zero. It can be used to avoid `msg.value` stuck in the contract
     * if an upgrade doesn't perform an initialization call.
     */
    function _checkNonPayable() private {
        if (msg.value > 0) {
            revert ERC1967NonPayable();
        }
    }
}

// lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/utils/SafeERC20.sol)

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    /**
     * @dev An operation with an ERC20 token failed.
     */
    error SafeERC20FailedOperation(address token);

    /**
     * @dev Indicates a failed `decreaseAllowance` request.
     */
    error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `requestedDecrease`. If `token` returns no
     * value, non-reverting calls are assumed to be successful.
     */
    function safeDecreaseAllowance(IERC20 token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
     * to be set to zero before setting it to a non-zero value, such as USDT.
     */
    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeCall(token.approve, (spender, value));

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeCall(token.approve, (spender, 0)));
            _callOptionalReturn(token, approvalCall);
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address-functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data);
        if (returndata.length != 0 && !abi.decode(returndata, (bool))) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturn} that silents catches all reverts and returns a bool instead.
     */
    function _callOptionalReturnBool(IERC20 token, bytes memory data) private returns (bool) {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We cannot use {Address-functionCall} here since this should return false
        // and not revert is the subcall reverts.

        (bool success, bytes memory returndata) = address(token).call(data);
        return success && (returndata.length == 0 || abi.decode(returndata, (bool))) && address(token).code.length > 0;
    }
}

// src/library/ToolLib.sol

library ToolLib {
    uint256 private constant DECIMALS = 1e18;
    uint256 public constant SECONDS_PER_BLOCK = 6;

    function LnUint256(uint256 value) internal pure returns (uint256) {
        bytes16 v = ABDKMathQuad.ln(ABDKMathQuad.fromUInt(value));
        return getLnValue(v);
    }

    function getLnValue(bytes16 value) internal pure returns (uint256) {
        return ABDKMathQuad.toUInt(ABDKMathQuad.mul(value, ABDKMathQuad.fromUInt(DECIMALS)));
    }

    function safeDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "Division by zero");

        bytes16 scaledA = ABDKMathQuad.fromUInt(a * DECIMALS);

        bytes16 result = ABDKMathQuad.div(scaledA, ABDKMathQuad.fromUInt(b));

        return ABDKMathQuad.toUInt(result);
    }

    function getDecimals() internal pure returns (uint256) {
        return DECIMALS;
    }

    function contains(bytes memory str, bytes memory substr) internal pure returns (bool) {
        if (str.length < substr.length) {
            return false;
        }
        for (uint256 i = 0; i <= str.length - substr.length; i++) {
            bool find = true;
            for (uint256 j = 0; j < substr.length; j++) {
                if (bytes1(str[i + j]) != bytes1(substr[j])) {
                    find = false;
                    break;
                }
            }
            if (find) {
                return true;
            }
        }
        return false;
    }

    function hasNumberGreaterThan20(string memory str) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        uint256 num = 0;
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] >= "0" && strBytes[i] <= "9") {
                num = num * 10 + (uint8(strBytes[i]) - uint8(bytes1("0")));
            } else if (num != 0) {
                if (num >= 20) {
                    return true;
                }
                num = 0;
            }
        }
        return num > 20;
    }

    function checkString(string memory text) internal pure returns (bool) {
        bool hasNvidia = contains(bytes(text), bytes("NVIDIA"));

        bool has = hasNumberGreaterThan20(text);

        return hasNvidia && has;
    }
}

// lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (proxy/utils/UUPSUpgradeable.sol)

/**
 * @dev An upgradeability mechanism designed for UUPS proxies. The functions included here can perform an upgrade of an
 * {ERC1967Proxy}, when this contract is set as the implementation behind such a proxy.
 *
 * A security mechanism ensures that an upgrade does not turn off upgradeability accidentally, although this risk is
 * reinstated if the upgrade retains upgradeability but removes the security mechanism, e.g. by replacing
 * `UUPSUpgradeable` with a custom implementation of upgrades.
 *
 * The {_authorizeUpgrade} function must be overridden to include access restriction to the upgrade mechanism.
 */
abstract contract UUPSUpgradeable is Initializable, IERC1822Proxiable {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address private immutable __self = address(this);

    /**
     * @dev The version of the upgrade interface of the contract. If this getter is missing, both `upgradeTo(address)`
     * and `upgradeToAndCall(address,bytes)` are present, and `upgradeTo` must be used if no function should be called,
     * while `upgradeToAndCall` will invoke the `receive` function if the second argument is the empty byte string.
     * If the getter returns `"5.0.0"`, only `upgradeToAndCall(address,bytes)` is present, and the second argument must
     * be the empty byte string if no function should be called, making it impossible to invoke the `receive` function
     * during an upgrade.
     */
    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    /**
     * @dev The call is from an unauthorized context.
     */
    error UUPSUnauthorizedCallContext();

    /**
     * @dev The storage `slot` is unsupported as a UUID.
     */
    error UUPSUnsupportedProxiableUUID(bytes32 slot);

    /**
     * @dev Check that the execution is being performed through a delegatecall call and that the execution context is
     * a proxy contract with an implementation (as defined in ERC1967) pointing to self. This should only be the case
     * for UUPS and transparent proxies that are using the current contract as their implementation. Execution of a
     * function through ERC1167 minimal proxies (clones) would not normally pass this test, but is not guaranteed to
     * fail.
     */
    modifier onlyProxy() {
        _checkProxy();
        _;
    }

    /**
     * @dev Check that the execution is not being performed through a delegate call. This allows a function to be
     * callable on the implementing contract but not through proxies.
     */
    modifier notDelegated() {
        _checkNotDelegated();
        _;
    }

    function __UUPSUpgradeable_init() internal onlyInitializing {
    }

    function __UUPSUpgradeable_init_unchained() internal onlyInitializing {
    }
    /**
     * @dev Implementation of the ERC1822 {proxiableUUID} function. This returns the storage slot used by the
     * implementation. It is used to validate the implementation's compatibility when performing an upgrade.
     *
     * IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this risks
     * bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that this
     * function revert if invoked through a proxy. This is guaranteed by the `notDelegated` modifier.
     */
    function proxiableUUID() external view virtual notDelegated returns (bytes32) {
        return ERC1967Utils.IMPLEMENTATION_SLOT;
    }

    /**
     * @dev Upgrade.s.sol the implementation of the proxy to `newImplementation`, and subsequently execute the function call
     * encoded in `data`.
     *
     * Calls {_authorizeUpgrade}.
     *
     * Emits an {Upgraded} event.
     *
     * @custom:oz-upgrades-unsafe-allow-reachable delegatecall
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) public payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data);
    }

    /**
     * @dev Reverts if the execution is not performed via delegatecall or the execution
     * context is not of a proxy with an ERC1967-compliant implementation pointing to self.
     * See {_onlyProxy}.
     */
    function _checkProxy() internal view virtual {
        if (
            address(this) == __self || // Must be called through delegatecall
            ERC1967Utils.getImplementation() != __self // Must be called through an active proxy
        ) {
            revert UUPSUnauthorizedCallContext();
        }
    }

    /**
     * @dev Reverts if the execution is performed via delegatecall.
     * See {notDelegated}.
     */
    function _checkNotDelegated() internal view virtual {
        if (address(this) != __self) {
            // Must not be called through delegatecall
            revert UUPSUnauthorizedCallContext();
        }
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
     * {upgradeToAndCall}.
     *
     * Normally, this function will use an xref:access.adoc[access control] modifier such as {Ownable-onlyOwner}.
     *
     * ```solidity
     * function _authorizeUpgrade(address) internal onlyOwner {}
     * ```
     */
    function _authorizeUpgrade(address newImplementation) internal virtual;

    /**
     * @dev Performs an implementation upgrade with a security check for UUPS proxies, and additional setup call.
     *
     * As a security check, {proxiableUUID} is invoked in the new implementation, and the return value
     * is expected to be the implementation slot in ERC1967.
     *
     * Emits an {IERC1967-Upgraded} event.
     */
    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data) private {
        try IERC1822Proxiable(newImplementation).proxiableUUID() returns (bytes32 slot) {
            if (slot != ERC1967Utils.IMPLEMENTATION_SLOT) {
                revert UUPSUnsupportedProxiableUUID(slot);
            }
            ERC1967Utils.upgradeToAndCall(newImplementation, data);
        } catch {
            // The implementation is not UUPS
            revert ERC1967Utils.ERC1967InvalidImplementation(newImplementation);
        }
    }
}

// src/interface/IDBCAIContract.sol

interface IDBCAIContract {
    function getMachineState(string calldata machineId, string calldata projectName, NFTStaking.StakingType stakingType)
        external
        view
        returns (bool isOnline, bool isRegistered);

    function getMachineInfo(string calldata id, bool isDeepLink)
        external
        view
        returns (
            address machineOwner,
            uint256 calcPoint,
            uint256 cpuRate,
            string memory gpuType,
            uint256 gpuMem,
            string memory cpuType,
            uint256 gpuCount,
            string memory machineId,
            uint256 memorySize
        );

    function freeGpuAmount(string calldata) external pure returns (uint256);

    function reportStakingStatus(
        string calldata projectName,
        NFTStaking.StakingType stakingType,
        string calldata id,
        uint256 gpuNum,
        bool isStake
    ) external;
}

// src/NFTStaking.sol

/// @custom:oz-upgrades-from OldNFTStaking
contract NFTStaking is
    NFTStakingState,
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IERC1155Receiver
{
    string public constant PROJECT_NAME = "DeepLinkEVM";
    uint8 public constant SECONDS_PER_BLOCK = 6;
    uint256 public constant BASE_RESERVE_AMOUNT = 10_000 ether;
    uint256 public constant REWARD_DURATION = 60 days;
    uint8 public constant MAX_NFTS_PER_MACHINE = 20;
    uint256 public constant LOCK_PERIOD = 180 days;
    StakingType public constant STAKING_TYPE = StakingType.ShortTerm;

    IDBCAIContract public dbcAIContract;
    IERC1155 public nftToken;
    IRewardToken public rewardToken;
    address public longStakeContractAddress;

    address public canUpgradeAddress;
    uint256 public totalDistributedRewardAmount;
    uint256 public rewardStartGPUThreshold;
    uint256 public rewardStartAtTimestamp;

    uint256 public initRewardAmount;
    bool public depositedReward;

    uint256 public totalAdjustUnit;
    uint256 public dailyRewardAmount;

    uint256 public totalStakingGpuCount;
    RewardCalculatorLib.RewardsPerShare public rewardsPerCalcPoint;

    string[] public stakedMachineIds;

    enum StakingType {
        ShortTerm,
        LongTerm,
        Free
    }

    enum MachineStatus {
        Normal,
        Blocking
    }

    struct LockedRewardDetail {
        uint256 totalAmount;
        uint256 lockTime;
        uint256 unlockTime;
        uint256 claimedAmount;
    }

    struct ApprovedReportInfo {
        address renter;
    }

    struct StakeInfo {
        address holder;
        uint256 startAtTimestamp;
        uint256 lastClaimAtTimestamp;
        uint256 endAtTimestamp;
        uint256 calcPoint;
        uint256 reservedAmount;
        uint256[] nftTokenIds;
        uint256[] tokenIdBalances;
        uint256 nftCount;
        uint256 claimedAmount;
        bool isRentedByUser;
        uint256 gpuCount;
        uint256 nextRenterCanRentAt;
    }

    struct BeneficiaryInfo {
        address beneficiary;
        uint256 rate;
    }

    mapping(address => bool) public dlcClientWalletAddress;
    mapping(address => string[]) public holder2MachineIds;
    mapping(string => LockedRewardDetail[]) public machineId2LockedRewardDetails;
    mapping(string => ApprovedReportInfo[]) private pendingSlashedMachineId2Renter;
    mapping(string => StakeInfo) public machineId2StakeInfos;
    mapping(string => LockedRewardDetail) public machineId2LockedRewardDetail;
    mapping(string => bool) public machineId2Rented;
    mapping(string => RewardCalculatorLib.UserRewards) public machineId2StakeUnitRewards;
    mapping(string => bool) private statedMachinesMap;

    uint256 public constant rewardPerShareAtRewardStart = 770415857426136133;
    uint256 public constant SLASH_AMOUNT = 1_000 ether;
    uint256 public phase;

    mapping(string => bool) private machineId2Personal;
    mapping(string => uint256) public machineId2ExtraRentFeeInUSDPerMinutes;
    uint256 public maxExtraRentFeeInUSDPerMinutes;

    mapping(string => MachineStatus) public machineId2MachineStatus;

    BeneficiaryInfo[] public globalBeneficiaryInfos;
    mapping(string => BeneficiaryInfo[]) public machineId2BeneficiaryInfos;

    uint256 public platformFeeRate;

    event Staked(
        address indexed stakeholder, string machineId, uint256 originCalcPoint, uint256 calcPoint, uint256 stakeHours
    );

    event StakedGPUType(string machineId, string gpuType);
    event AddedStakeHours(address indexed stakeholder, string machineId, uint256 stakeHours);

    event ReserveDLC(string machineId, uint256 amount);
    event Unstaked(address indexed stakeholder, string machineId, uint256 paybackReserveAmount);
    event Claimed(
        address indexed stakeholder,
        string machineId,
        uint256 totalRewardAmount,
        uint256 moveToUserWalletAmount,
        uint256 moveToReservedAmount,
        bool paidSlash
    );

    event PaySlash(string machineId, address renter, uint256 slashAmount);
    event RentMachine(address indexed machineOwner, string machineId, uint256 rentFee);
    event EndRentMachineFee(address indexed machineOwner, string machineId, uint256 baseRentFee, uint256 extraRentFee);
    event EndRentMachine(address indexed machineOwner, string machineId, uint256 nextCanRentTime);
    event ReportMachineFault(string machineId, address renter);
    event ReportMachineFaultLight(string machineId, address renter, uint256 nextCanRentTime);
    event RewardsPerCalcPointUpdate(uint256 accumulatedPerShareBefore, uint256 accumulatedPerShareAfter);
    event MoveToReserveAmount(string machineId, address holder, uint256 amount);
    event RenewRent(string machineId, address holder, uint256 rentFee);
    event AfterAddHoursEndTime(string machineId, uint256 endTimestamp);
    event ExitStakingForOffline(string machineId, address holder);
    event ExitStakingForBlocking(string machineId, address holder);

    event RecoverRewarding(string machineId, address holder);
    event RecoverRewardingForBlocking(string machineId, address holder);
    event MachineUnregistered(string machineId);
    event MachineRegistered(string machineId);
    // error

    error CallerNotRentContract();
    error ZeroAddress();
    error AddressExists();
    error CanNotUpgrade(address);
    error TimestampLessThanCurrent();
    error MachineNotStaked(string machineId);
    error MachineIsStaking(string machineId);
    error StakeAmountLessThanReserve(string machineId, uint256 amount);
    error MemorySizeLessThan16G(uint256 mem);
    error GPUTypeNotMatch(string gpuType);
    error ZeroCalcPoint();
    error InvalidNFTLength(uint256 tokenIdLength, uint256 balanceLength);
    error NotMachineOwner(address);
    error ZeroNFTTokenIds();
    error NFTCountGreaterThan20();
    error NotPaidSlashBeforeClaim(string machineId, uint256 slashAmount);
    error NotStakeHolder(string machineId, address currentAddress);
    error MachineRentedByUser();
    error MachineNotRented();
    error NotAdmin();
    error MachineNotStakeEnoughDBC();
    error InvalidStakeHours();
    error RewardEnd();
    error MachineNotOnlineOrRegistered();
    error NotMachineOwnerOrAdmin();
    error MachineStillRegistered();
    error StakingInLongTerm();
    error IsStaking();
    error MachineHasUnpaidSlash(string machineId);
    error InRenting();
    error RewardNotEnough();
    error IsPersonalMachine();
    error MaxRentExtraFeeNotSet();
    error CanNotOverExtraFeeLimit(uint256 maxFee);
    error TotalRateNotEq100();
    error StakeNotEnd();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function onERC1155BatchReceived(
        address, /* unusedParameter */
        address, /* unusedParameter */
        uint256[] calldata, /* unusedParameter */
        uint256[] calldata, /* unusedParameter */
        bytes calldata /* unusedParameter */
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function onERC1155Received(
        address, /* unusedParameter */
        address, /* unusedParameter */
        uint256, /* unusedParameter */
        uint256, /* unusedParameter */
        bytes calldata /* unusedParameter */
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }

    modifier onlyRentContract() {
        require(msg.sender == address(rentContract), CallerNotRentContract());
        _;
    }

    modifier onlyDLCClientWallet() {
        require(dlcClientWalletAddress[msg.sender] || msg.sender == owner(), NotAdmin());
        _;
    }

    modifier isValidConfigs(BeneficiaryInfo[] calldata globalBeneficiaryInfos_) {
        uint256 totalRate;
        for (uint256 i = 0; i < globalBeneficiaryInfos_.length; i++) {
            require(globalBeneficiaryInfos_[i].beneficiary != address(0), ZeroAddress());
            totalRate += globalBeneficiaryInfos_[i].rate;
        }
        require(totalRate == 100 || (totalRate == 0 && globalBeneficiaryInfos_.length == 1), TotalRateNotEq100());
        _;
    }

    modifier canStake(
        address stakeholder,
        string memory machineId,
        uint256 stakeHours,
        uint256[] memory nftTokenIds,
        uint256[] memory nftTokenIdBalances
    ) {
        require(dlcClientWalletAddress[msg.sender], NotAdmin());
        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.nftTokenIds.length == 0, IsStaking());
        require(dbcAIContract.freeGpuAmount(machineId) >= 1, MachineNotStakeEnoughDBC());
        require(
            nftTokenIds.length == nftTokenIdBalances.length,
            InvalidNFTLength(nftTokenIds.length, nftTokenIdBalances.length)
        );

        require((stakeHours >= 2), InvalidStakeHours());
        require((stakeHours <= 4320), InvalidStakeHours());

        require(!rewardEnd(), RewardEnd());
        (bool isOnline, bool isRegistered) = dbcAIContract.getMachineState(machineId, PROJECT_NAME, STAKING_TYPE);
        require(isOnline && isRegistered, MachineNotOnlineOrRegistered());
        require(!isStaking(machineId), MachineIsStaking(machineId));
        require(nftTokenIds.length > 0, ZeroNFTTokenIds());
        if (longStakeContractAddress != address(0)) {
            require(!ILongStakeContract(longStakeContractAddress).isStaking(machineId), StakingInLongTerm());
        }
        // try-catch: 兼容旧版 Rent 合约（无 hasUnpaidSlash 函数时跳过检查）
        try rentContract.hasUnpaidSlash(machineId) returns (bool unpaid) {
            require(!unpaid, MachineHasUnpaidSlash(machineId));
        } catch {}
        _;
    }

    function initialize(
        address _initialOwner,
        address _nftToken,
        address _rewardToken,
        address _rentContract,
        address _dbcAIContract,
        uint8 phaseLevel
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();

        rewardToken = IRewardToken(_rewardToken);
        nftToken = IERC1155(_nftToken);
        rentContract = IRentContract(_rentContract);
        dbcAIContract = IDBCAIContract(_dbcAIContract);

        if (phaseLevel == 1) {
            rewardStartGPUThreshold = 500;
            initRewardAmount = 180_000_000 ether;
        }
        if (phaseLevel == 2) {
            rewardStartGPUThreshold = 1000;
            initRewardAmount = 240_000_000 ether;
        }
        if (phaseLevel == 3) {
            rewardStartGPUThreshold = 2_000;
            initRewardAmount = 580_000_000 ether;
        }

        dailyRewardAmount = initRewardAmount / 60;

        canUpgradeAddress = msg.sender;
        rewardsPerCalcPoint.lastUpdated = block.timestamp;
    }

    function getRewardDuration() public view returns (uint256) {
        if (phase <= 1) {
            return REWARD_DURATION;
        }
        if (phase == 2) {
            return REWARD_DURATION * 2;
        }
        if (phase == 3) {
            return REWARD_DURATION * 3;
        }
        if (phase == 4) {
            return REWARD_DURATION * 4;
        }
        if (phase == 5) {
            return REWARD_DURATION * 5;
        }
        if (phase == 6) {
            return REWARD_DURATION * 7;  // 300天 + 120天 = 420天
        }
        return 0;
    }

    function setPhase(uint8 _phase) external onlyOwner {
        require(_phase >= 1 && _phase <= 6, "Invalid phase");
        // require(rewardEnd(), "Current phaseReward not end");
        phase = _phase;

        if (phase == 1) {
            initRewardAmount = 180_000_000 ether;
        }
        if (phase == 2) {
            initRewardAmount =  240_000_000 ether;
        }
        if (phase == 3 || phase == 4 || phase == 5 || phase == 6) {
            initRewardAmount =  580_000_000 ether;
        }

        dailyRewardAmount = initRewardAmount / 60;
    }

    function setThreshold(uint256 _threshold) public onlyOwner {
        rewardStartGPUThreshold = _threshold;
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        require(newImplementation != address(0), ZeroAddress());
        require(msg.sender == canUpgradeAddress, CanNotUpgrade(msg.sender));
    }

    function setUpgradeAddress(address addr) external onlyOwner {
        canUpgradeAddress = addr;
    }

    function setRewardToken(address token) external onlyOwner {
        rewardToken = IRewardToken(token);
    }

    function setRentContract(address _rentContract) external onlyOwner {
        rentContract = IRentContract(_rentContract);
    }

    function setNftToken(address token) external onlyOwner {
        nftToken = IERC1155(token);
    }

    function setLongStakeContract(address _longStakeContract) public onlyOwner {
        longStakeContractAddress = _longStakeContract;
    }

    function setRewardStartAt(uint256 timestamp) external onlyOwner {
        require(timestamp >= block.timestamp, TimestampLessThanCurrent());
        rewardStartAtTimestamp = timestamp;
    }

    function setDLCClientWallets(address[] calldata addrs) external onlyOwner {
        for (uint256 i = 0; i < addrs.length; i++) {
            require(addrs[i] != address(0), ZeroAddress());
            require(dlcClientWalletAddress[addrs[i]] == false, AddressExists());
            dlcClientWalletAddress[addrs[i]] = true;
        }
    }

    function validateMachineIds(string[] memory machineIds, bool isValid) external onlyDLCClientWallet {
        for (uint256 i = 0; i < machineIds.length; i++) {
            string memory machineId = machineIds[i];
            MachineStatus oldStatus = machineId2MachineStatus[machineId];
            if (isValid && oldStatus == MachineStatus.Blocking) {
                machineId2MachineStatus[machineId] = MachineStatus.Normal;
                _recoverRewarding(machineId,true);
            } else if (!isValid && oldStatus == MachineStatus.Normal) {
                machineId2MachineStatus[machineId] = MachineStatus.Blocking;
                _stopRewarding(machineId,true);
            }
        }
    }

    function setDBCAIContract(address addr) external onlyOwner {
        dbcAIContract = IDBCAIContract(addr);
    }

    function addDLCToStake(string memory machineId, uint256 amount) external onlyDLCClientWallet nonReentrant {
        require(isStaking(machineId), MachineNotStaked(machineId));
        if (amount == 0) {
            return;
        }
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        ApprovedReportInfo[] memory approvedReportInfos = pendingSlashedMachineId2Renter[machineId];

        if (approvedReportInfos.length > 0) {
            require(
                amount == BASE_RESERVE_AMOUNT * approvedReportInfos.length,
                StakeAmountLessThanReserve(machineId, amount)
            );
            for (uint8 i = 0; i < approvedReportInfos.length; i++) {
                // pay slash to renters
                payToRenterForSlashing(machineId, stakeInfo, approvedReportInfos[i].renter, false);
                amount -= BASE_RESERVE_AMOUNT;
            }
            delete pendingSlashedMachineId2Renter[machineId];
        }

        _joinStaking(machineId, stakeInfo.calcPoint, amount + stakeInfo.reservedAmount);
        //        NFTStakingState.addReserveAmount(machineId, stakeInfo.holder, amount);
        emit ReserveDLC(machineId, amount);
    }

    function revertIfMachineInfoCanNotStake(uint256 calcPoint, string memory gpuType, uint256 mem) internal pure {
        require(mem >= 16, MemorySizeLessThan16G(mem));
        require(ToolLib.checkString(gpuType), GPUTypeNotMatch(gpuType));
        require(calcPoint > 0, ZeroCalcPoint());
    }

    function _tryInitMachineLockRewardInfo(string memory machineId, uint256 currentTime) internal {
        if (machineId2LockedRewardDetail[machineId].lockTime == 0) {
            machineId2LockedRewardDetail[machineId] = LockedRewardDetail({
                totalAmount: 0,
                lockTime: currentTime,
                unlockTime: currentTime + LOCK_PERIOD,
                claimedAmount: 0
            });
        }
    }

    function stakeV2(
        address stakeholder,
        string calldata machineId,
        uint256[] calldata nftTokenIds,
        uint256[] calldata nftTokenIdBalances,
        uint256 stakeHours,
        bool _isPersonalMachine
    )
        external
        onlyDLCClientWallet
        canStake(stakeholder, machineId, stakeHours, nftTokenIds, nftTokenIdBalances)
        nonReentrant
    {
        (address machineOwner, uint256 calcPoint,, string memory gpuType,,,,, uint256 mem) =
            dbcAIContract.getMachineInfo(machineId, true);
        require(machineOwner == stakeholder, NotMachineOwner(machineOwner));
        revertIfMachineInfoCanNotStake(calcPoint, gpuType, mem);

        uint256 nftCount = getNFTCount(nftTokenIdBalances);
        require(nftCount <= MAX_NFTS_PER_MACHINE, NFTCountGreaterThan20());
        uint256 originCalcPoint = calcPoint;
        calcPoint = calcPoint * nftCount;
        uint256 currentTime = block.timestamp;
        uint256 stakeEndAt = 0;
        if (stakeHours > 0) {
            stakeEndAt = currentTime + stakeHours * 1 hours;
        }

        uint8 gpuCount = 1;
        if (!statedMachinesMap[machineId]) {
            statedMachinesMap[machineId] = true;
            totalGpuCount += gpuCount;
        }

        machineId2Personal[machineId] = _isPersonalMachine;

        totalStakingGpuCount += gpuCount;
        if (totalGpuCount >= rewardStartGPUThreshold && rewardStartAtTimestamp == 0) {
            rewardStartAtTimestamp = currentTime;
        }

        nftToken.safeBatchTransferFrom(stakeholder, address(this), nftTokenIds, nftTokenIdBalances, "transfer");
        machineId2StakeInfos[machineId] = StakeInfo({
            startAtTimestamp: currentTime,
            lastClaimAtTimestamp: currentTime,
            endAtTimestamp: stakeEndAt,
            calcPoint: 0,
            reservedAmount: 0,
            nftTokenIds: nftTokenIds,
            tokenIdBalances: nftTokenIdBalances,
            nftCount: nftCount,
            holder: stakeholder,
            claimedAmount: 0,
            isRentedByUser: false,
            gpuCount: gpuCount,
            nextRenterCanRentAt: currentTime
        });

        _joinStaking(machineId, calcPoint, 0);
        _tryInitMachineLockRewardInfo(machineId, currentTime);

        holder2MachineIds[stakeholder].push(machineId);
        dbcAIContract.reportStakingStatus(PROJECT_NAME, StakingType.ShortTerm, machineId, 1, true);
        emit Staked(stakeholder, machineId, originCalcPoint, calcPoint, stakeHours);
        emit StakedGPUType(machineId, gpuType);
    }

    function stake(
        address stakeholder,
        string calldata machineId,
        uint256[] calldata nftTokenIds,
        uint256[] calldata nftTokenIdBalances,
        uint256 stakeHours
    )
        external
        onlyDLCClientWallet
        canStake(stakeholder, machineId, stakeHours, nftTokenIds, nftTokenIdBalances)
        nonReentrant
    {
        (address machineOwner, uint256 calcPoint,, string memory gpuType,,,,, uint256 mem) =
            dbcAIContract.getMachineInfo(machineId, true);
        require(machineOwner == stakeholder, NotMachineOwner(machineOwner));
        revertIfMachineInfoCanNotStake(calcPoint, gpuType, mem);

        uint256 nftCount = getNFTCount(nftTokenIdBalances);
        require(nftCount <= MAX_NFTS_PER_MACHINE, NFTCountGreaterThan20());
        uint256 originCalcPoint = calcPoint;
        calcPoint = calcPoint * nftCount;
        uint256 currentTime = block.timestamp;
        uint256 stakeEndAt = 0;
        if (stakeHours > 0) {
            stakeEndAt = currentTime + stakeHours * 1 hours;
        }

        uint8 gpuCount = 1;
        if (!statedMachinesMap[machineId]) {
            statedMachinesMap[machineId] = true;
            totalGpuCount += gpuCount;
        }

        totalStakingGpuCount += gpuCount;
        if (totalGpuCount >= rewardStartGPUThreshold && rewardStartAtTimestamp == 0) {
            rewardStartAtTimestamp = currentTime;
        }

        nftToken.safeBatchTransferFrom(stakeholder, address(this), nftTokenIds, nftTokenIdBalances, "transfer");
        machineId2StakeInfos[machineId] = StakeInfo({
            startAtTimestamp: currentTime,
            lastClaimAtTimestamp: currentTime,
            endAtTimestamp: stakeEndAt,
            calcPoint: 0,
            reservedAmount: 0,
            nftTokenIds: nftTokenIds,
            tokenIdBalances: nftTokenIdBalances,
            nftCount: nftCount,
            holder: stakeholder,
            claimedAmount: 0,
            isRentedByUser: rentContract.isRented(machineId),
            gpuCount: gpuCount,
            nextRenterCanRentAt: currentTime
        });

        _joinStaking(machineId, calcPoint, 0);
        _tryInitMachineLockRewardInfo(machineId, currentTime);

        holder2MachineIds[stakeholder].push(machineId);
        dbcAIContract.reportStakingStatus(PROJECT_NAME, StakingType.ShortTerm, machineId, 1, true);
        emit Staked(stakeholder, machineId, originCalcPoint, calcPoint, stakeHours);
        emit StakedGPUType(machineId, gpuType);
    }

    function addStakeHours(string memory machineId, uint256 additionHours) external {
        require(additionHours >= 2, InvalidStakeHours());
        require(additionHours <= 4320, InvalidStakeHours());
        uint256 additionSeconds = additionHours * 1 hours;

        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.holder == msg.sender, NotStakeHolder(machineId, msg.sender));
        require(block.timestamp < stakeInfo.endAtTimestamp, MachineNotStaked(machineId));

        stakeInfo.endAtTimestamp += additionSeconds;

        // 修复：endRentMachine 在质押即将到期时将 nextRenterCanRentAt 设为 0（禁止新租赁），
        // 增加时长后质押已续期，需将 nextRenterCanRentAt 恢复为可租状态
        if (stakeInfo.nextRenterCanRentAt == 0 && !stakeInfo.isRentedByUser) {
            stakeInfo.nextRenterCanRentAt = block.timestamp;
        }

        emit AddedStakeHours(msg.sender, machineId, additionHours);
        emit AfterAddHoursEndTime(machineId, stakeInfo.endAtTimestamp);
    }

    function machineIsBlocked(string memory machineId) external view returns (bool) {
        MachineStatus status = machineId2MachineStatus[machineId];
        return status == MachineStatus.Blocking;
    }

    function setMaxExtraRentFeeInUSDPerMinutes(uint256 feeInUSD) external onlyDLCClientWallet {
        maxExtraRentFeeInUSDPerMinutes = feeInUSD;
    }

    function getMachineExtraRentFee(string memory machineId) external view returns (uint256) {
        return machineId2ExtraRentFeeInUSDPerMinutes[machineId];
    }

    function setExtraRentFeeInUSDPerMinutes(string calldata machineId, uint256 feeInUSD) external {
        require(!machineId2Personal[machineId], IsPersonalMachine());
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(msg.sender == stakeInfo.holder, NotMachineOwner(msg.sender));
        require(maxExtraRentFeeInUSDPerMinutes > 0, MaxRentExtraFeeNotSet());
        require(feeInUSD <= maxExtraRentFeeInUSDPerMinutes, CanNotOverExtraFeeLimit(maxExtraRentFeeInUSDPerMinutes));

        machineId2ExtraRentFeeInUSDPerMinutes[machineId] = feeInUSD;
    }

    function getPendingSlashCount(string memory machineId) public view returns (uint256) {
        return pendingSlashedMachineId2Renter[machineId].length;
    }

    function getRewardInfo(string memory machineId)
        public
        view
        returns (uint256 newRewardAmount, uint256 canClaimAmount, uint256 lockedAmount, uint256 claimedAmount)
    {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        uint256 totalRewardAmount = calculateRewards(machineId);
        (uint256 _canClaimAmount, uint256 _lockedAmount) = _getRewardDetail(totalRewardAmount);
        (uint256 releaseAmount, uint256 lockedAmountBefore) = calculateReleaseReward(machineId);

        return (
            totalRewardAmount,
            _canClaimAmount + releaseAmount,
            _lockedAmount + lockedAmountBefore,
            stakeInfo.claimedAmount
        );
    }

    function getNFTCount(uint256[] memory nftTokenIdBalances) internal pure returns (uint256 nftCount) {
        for (uint256 i = 0; i < nftTokenIdBalances.length; i++) {
            nftCount += nftTokenIdBalances[i];
        }

        return nftCount;
    }

    function _claim(string memory machineId) internal {
        if (!rewardStart()) {
            return;
        }

        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        uint256 machineShares = _getMachineShares(stakeInfo.calcPoint, stakeInfo.reservedAmount);
        _updateMachineRewards(machineId, machineShares);

        address stakeholder = stakeInfo.holder;
        uint256 currentTimestamp = block.timestamp;

        bool _isStaking = isStaking(machineId);
        uint256 rewardAmount = calculateRewards(machineId);

        machineId2StakeUnitRewards[machineId].accumulated = 0;

        (uint256 canClaimAmount, uint256 lockedAmount) = _getRewardDetail(rewardAmount);

        (uint256 _dailyReleaseAmount,) = calculateReleaseRewardAndUpdate(machineId);
        canClaimAmount += _dailyReleaseAmount;

        ApprovedReportInfo[] storage approvedReportInfos = pendingSlashedMachineId2Renter[machineId];
        bool slashed = approvedReportInfos.length > 0;
        uint256 moveToReserveAmount = 0;
        if (canClaimAmount > 0 && (_isStaking || slashed)) {
            if (stakeInfo.reservedAmount < BASE_RESERVE_AMOUNT) {
                (uint256 _moveToReserveAmount, uint256 leftAmountCanClaim) =
                    tryMoveReserve(machineId, canClaimAmount, stakeInfo);
                canClaimAmount = leftAmountCanClaim;
                moveToReserveAmount = _moveToReserveAmount;
            }
        }

        bool paidSlash = false;
        if (slashed && stakeInfo.reservedAmount >= SLASH_AMOUNT) {
            ApprovedReportInfo memory lastSlashInfo = approvedReportInfos[approvedReportInfos.length - 1];
            payToRenterForSlashing(machineId, stakeInfo, lastSlashInfo.renter, true);
            approvedReportInfos.pop();
            paidSlash = true;
            //            NFTStakingState.subReserveAmount(msg.sender, machineId, BASE_RESERVE_AMOUNT);
        }

        if (stakeInfo.reservedAmount < BASE_RESERVE_AMOUNT && _isStaking) {
            (uint256 _moveToReserveAmount, uint256 leftAmountCanClaim) =
                tryMoveReserve(machineId, canClaimAmount, stakeInfo);
            canClaimAmount = leftAmountCanClaim;
            moveToReserveAmount = _moveToReserveAmount;
        }

        if (canClaimAmount > 0) {
            require(rewardToken.balanceOf(address(this)) - totalReservedAmount >= canClaimAmount, RewardNotEnough());
            SafeERC20.safeTransfer(rewardToken, stakeholder, canClaimAmount);
        }

        uint256 totalRewardAmount = canClaimAmount + moveToReserveAmount;
        totalDistributedRewardAmount += totalRewardAmount;
        stakeInfo.claimedAmount += totalRewardAmount;
        stakeInfo.lastClaimAtTimestamp = currentTimestamp;
        //        NFTStakingState.addClaimedRewardAmount(
        //            msg.sender, machineId, rewardAmount + _dailyReleaseAmount, totalRewardAmount
        //        );

        if (lockedAmount > 0) {
            machineId2LockedRewardDetail[machineId].totalAmount += lockedAmount;
        }

        emit Claimed(
            stakeholder, machineId, rewardAmount + _dailyReleaseAmount, canClaimAmount, moveToReserveAmount, paidSlash
        );
    }

    function getMachineIdsByStakeholder(address holder) external view returns (string[] memory) {
        return holder2MachineIds[holder];
    }

    function getAllRewardInfo(address holder)
        external
        view
        returns (uint256 availableRewardAmount, uint256 canClaimAmount, uint256 lockedAmount, uint256 claimedAmount)
    {
        string[] memory machineIds = holder2MachineIds[holder];
        for (uint256 i = 0; i < machineIds.length; i++) {
            (uint256 _availableRewardAmount, uint256 _canClaimAmount, uint256 _lockedAmount, uint256 _claimedAmount) =
                getRewardInfo(machineIds[i]);
            availableRewardAmount += _availableRewardAmount;
            canClaimAmount += _canClaimAmount;
            lockedAmount += _lockedAmount;
            claimedAmount += _claimedAmount;
        }
        return (availableRewardAmount, canClaimAmount, lockedAmount, claimedAmount);
    }

    function endTime() external view returns (uint256) {
        return rewardStartAtTimestamp + getRewardDuration();
    }

    function claim(string memory machineId) public {
        address stakeholder = msg.sender;
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        require(stakeInfo.holder == stakeholder, NotStakeHolder(machineId, stakeholder));

        _claim(machineId);
    }

    function tryMoveReserve(string memory machineId, uint256 canClaimAmount, StakeInfo storage stakeInfo)
        internal
        returns (uint256 moveToReserveAmount, uint256 leftAmountCanClaim)
    {
        uint256 leftAmountShouldReserve = BASE_RESERVE_AMOUNT - stakeInfo.reservedAmount;
        if (canClaimAmount >= leftAmountShouldReserve) {
            canClaimAmount -= leftAmountShouldReserve;
            moveToReserveAmount = leftAmountShouldReserve;
        } else {
            moveToReserveAmount = canClaimAmount;
            canClaimAmount = 0;
        }

        // the amount should be transfer to reserve
        totalReservedAmount += moveToReserveAmount;
        stakeInfo.reservedAmount += moveToReserveAmount;
        //        NFTStakingState.addReserveAmount(machineId, stakeInfo.holder, moveToReserveAmount);
        if (moveToReserveAmount > 0) {
            emit MoveToReserveAmount(machineId, stakeInfo.holder, moveToReserveAmount);
        }
        return (moveToReserveAmount, canClaimAmount);
    }

    function renewRentMachine(string memory machineId, uint256 rentFee) external onlyRentAddress {
        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
        emit RenewRent(machineId, stakeInfo.holder, rentFee);
    }

    function calculateReleaseRewardAndUpdate(string memory machineId)
        internal
        returns (uint256 releaseAmount, uint256 lockedAmount)
    {
        LockedRewardDetail storage lockedRewardDetail = machineId2LockedRewardDetail[machineId];
        if (lockedRewardDetail.totalAmount > 0 && lockedRewardDetail.totalAmount == lockedRewardDetail.claimedAmount) {
            return (0, 0);
        }

        if (block.timestamp > lockedRewardDetail.unlockTime) {
            releaseAmount = lockedRewardDetail.totalAmount - lockedRewardDetail.claimedAmount;
            lockedRewardDetail.claimedAmount = lockedRewardDetail.totalAmount;
            return (releaseAmount, 0);
        }

        uint256 totalUnlocked =
            (block.timestamp - lockedRewardDetail.lockTime) * lockedRewardDetail.totalAmount / LOCK_PERIOD;
        releaseAmount = totalUnlocked - lockedRewardDetail.claimedAmount;
        lockedRewardDetail.claimedAmount += releaseAmount;
        return (releaseAmount, lockedRewardDetail.totalAmount - releaseAmount);
    }

    function calculateReleaseReward(string memory machineId)
        public
        view
        returns (uint256 releaseAmount, uint256 lockedAmount)
    {
        LockedRewardDetail storage lockedRewardDetail = machineId2LockedRewardDetail[machineId];
        if (lockedRewardDetail.totalAmount > 0 && lockedRewardDetail.totalAmount == lockedRewardDetail.claimedAmount) {
            return (0, 0);
        }

        if (block.timestamp > lockedRewardDetail.unlockTime) {
            releaseAmount = lockedRewardDetail.totalAmount - lockedRewardDetail.claimedAmount;
            return (releaseAmount, 0);
        }

        uint256 totalUnlocked =
            (block.timestamp - lockedRewardDetail.lockTime) * lockedRewardDetail.totalAmount / LOCK_PERIOD;
        releaseAmount = totalUnlocked - lockedRewardDetail.claimedAmount;
        return (releaseAmount, lockedRewardDetail.totalAmount - releaseAmount);
    }

    function unStake(string calldata machineId) public nonReentrant {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        if (msg.sender != address(rentContract)) {
            require(stakeInfo.startAtTimestamp > 0, MachineNotStaked(machineId));
            require(block.timestamp >= stakeInfo.endAtTimestamp, StakeNotEnd());
            require(!stakeInfo.isRentedByUser, MachineRentedByUser());
            // isRegistered check removed: staking expiry (StakeNotEnd) is sufficient protection.
            // _unStake() calls reportStakingStatus(false) to unregister automatically.
            // Previous check caused NFT lock-up when Detection Node didn't unregister expired machines.
        } else {
            emit ExitStakingForOffline(machineId, stakeInfo.holder);
        }
        _claim(machineId);
        _unStake(machineId, stakeInfo.holder);
    }

    function forceUnStake(string calldata machineId) external onlyOwner {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        _claim(machineId);
        _unStake(machineId, stakeInfo.holder);
    }

    /// @notice 强制清理质押记录（跳过 _claim，用于 slash 后 calcPoint=0 导致 _claim 溢出的情况）
    function forceCleanupStakeInfo(string calldata machineId) external onlyOwner {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.holder != address(0), "no stake info");
        address stakeholder = stakeInfo.holder;

        // 归还 NFT（如果合约中还持有）
        if (stakeInfo.nftTokenIds.length > 0) {
            try nftToken.safeBatchTransferFrom(
                address(this), stakeholder, stakeInfo.nftTokenIds, stakeInfo.tokenIdBalances, "transfer"
            ) {} catch {}
        }

        // 归还 reservedAmount
        uint256 reservedAmount = stakeInfo.reservedAmount;
        if (reservedAmount > 0) {
            stakeInfo.reservedAmount = 0;
            totalReservedAmount = totalReservedAmount > reservedAmount ? totalReservedAmount - reservedAmount : 0;
            try rewardToken.transfer(stakeholder, reservedAmount) {} catch {}
        }

        // 清理 totalCalcPoint / totalAdjustUnit
        if (stakeInfo.calcPoint > 0) {
            uint256 oldLnReserved = ToolLib.LnUint256(
                reservedAmount > BASE_RESERVE_AMOUNT ? reservedAmount : BASE_RESERVE_AMOUNT
            );
            uint256 shares = stakeInfo.calcPoint * oldLnReserved;
            totalAdjustUnit = totalAdjustUnit > shares ? totalAdjustUnit - shares : 0;
            totalCalcPoint = totalCalcPoint > stakeInfo.calcPoint ? totalCalcPoint - stakeInfo.calcPoint : 0;
        }

        // 清理 holder 列表
        removeStakingMachineFromHolder(stakeholder, machineId);
        if (totalStakingGpuCount > 0) {
            totalStakingGpuCount -= 1;
        }

        // 清理 stakeInfo
        delete machineId2StakeInfos[machineId];

        // 通知链上注册表
        try dbcAIContract.reportStakingStatus(PROJECT_NAME, StakingType.ShortTerm, machineId, 1, false) {} catch {}

        emit Unstaked(stakeholder, machineId, reservedAmount);
    }

    function unStakeByHolder(string calldata machineId) public nonReentrant {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(msg.sender == stakeInfo.holder, NotStakeHolder(machineId, msg.sender));
        require(stakeInfo.startAtTimestamp > 0, MachineNotStaked(machineId));
        require(stakeInfo.isRentedByUser == false, MachineRentedByUser());
        (, bool isRegistered) = dbcAIContract.getMachineState(machineId, PROJECT_NAME, STAKING_TYPE);
        require(!isRegistered, MachineStillRegistered());

        //        require(machineId2Rented[machineId] == false, InRenting());
        _claim(machineId);
        _unStake(machineId, stakeInfo.holder);
    }

    function _unStake(string calldata machineId, address stakeholder) internal {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        uint256 reservedAmount = stakeInfo.reservedAmount;

        if (reservedAmount > 0) {
            SafeERC20.safeTransfer(rewardToken, stakeholder, reservedAmount);
            stakeInfo.reservedAmount = 0;
            totalReservedAmount = totalReservedAmount > reservedAmount ? totalReservedAmount - reservedAmount : 0;
        }

        stakeInfo.endAtTimestamp = block.timestamp;
        nftToken.safeBatchTransferFrom(
            address(this), stakeholder, stakeInfo.nftTokenIds, stakeInfo.tokenIdBalances, "transfer"
        );
        stakeInfo.nftTokenIds = new uint256[](0);
        stakeInfo.tokenIdBalances = new uint256[](0);
        stakeInfo.nftCount = 0;
        _joinStaking(machineId, 0, 0);
        removeStakingMachineFromHolder(stakeholder, machineId);
        if (totalStakingGpuCount > 0) {
            totalStakingGpuCount -= 1;
        }

        //        NFTStakingState.removeMachine(stakeInfo.holder, machineId);
        // try-catch 防止跨合约重入导致 revert（dbcAI → Rent.notify → reportMachineFault → _unStake → dbcAI）
        try dbcAIContract.reportStakingStatus(PROJECT_NAME, StakingType.ShortTerm, machineId, 1, false) {} catch {}
        emit Unstaked(stakeholder, machineId, reservedAmount);
    }

    function removeStakingMachineFromHolder(address holder, string memory machineId) internal {
        string[] storage machineIds = holder2MachineIds[holder];
        for (uint256 i = 0; i < machineIds.length; i++) {
            if (keccak256(abi.encodePacked(machineIds[i])) == keccak256(abi.encodePacked(machineId))) {
                machineIds[i] = machineIds[machineIds.length - 1];
                machineIds.pop();
                break;
            }
        }
    }

    function getStakeHolder(string calldata machineId) external view returns (address) {
        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
        return stakeInfo.holder;
    }

    function isStaking(string memory machineId) public view returns (bool) {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        bool _isStaking = stakeInfo.holder != address(0) && stakeInfo.startAtTimestamp > 0;
        if (stakeInfo.endAtTimestamp != 0) {
            _isStaking = _isStaking && block.timestamp < stakeInfo.endAtTimestamp;
        }
        return _isStaking;
    }

    function getLeftGPUCountToStartReward() public view returns (uint256) {
        return rewardStartGPUThreshold > totalGpuCount ? rewardStartGPUThreshold - totalGpuCount : 0;
    }

    function rentMachine(string calldata machineId) external onlyRentContract {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        stakeInfo.isRentedByUser = true;

        (, uint256 calcPoint,,,,,,,) = dbcAIContract.getMachineInfo(machineId, true);

        calcPoint = calcPoint * getNFTCount(stakeInfo.tokenIdBalances);
        uint256 newCalcPoint = (calcPoint * 13) / 10;
        _joinStaking(machineId, newCalcPoint, stakeInfo.reservedAmount);
        if (!machineId2Rented[machineId]) {
            machineId2Rented[machineId] = true;
        }
        // rentFee move to RentMachineFee event, so set 0 in current RentMachine event
        emit RentMachine(stakeInfo.holder, machineId, 0);
    }

    function endRentMachine(string calldata machineId, uint256 baseRentFee, uint256 extraRentFee)
        external
        onlyRentContract
    {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.isRentedByUser, MachineNotRented());
        machineId2Rented[machineId] = false;
        if (stakeInfo.nftCount > 0) {
            stakeInfo.isRentedByUser = false;

            // 30 blocks
            stakeInfo.nextRenterCanRentAt = 300 + block.timestamp;
            if (block.timestamp > stakeInfo.endAtTimestamp - 1 hours) {
                stakeInfo.nextRenterCanRentAt = 0;
            }

            (, uint256 calcPoint,,,,,,,) = dbcAIContract.getMachineInfo(machineId, true);
            calcPoint = calcPoint * getNFTCount(stakeInfo.tokenIdBalances);
            _joinStaking(machineId, calcPoint, stakeInfo.reservedAmount);
        }

        delete machineId2BeneficiaryInfos[machineId];
        emit EndRentMachine(stakeInfo.holder, machineId, stakeInfo.nextRenterCanRentAt);
        emit EndRentMachineFee(stakeInfo.holder, machineId, baseRentFee, extraRentFee);
    }

    /// @notice 当机器离线且租赁已过期时，清理租赁状态
    /// @dev 用于处理租赁过期但未调用 endRentMachine 导致的状态不一致
    function endRentMachineWhenMachineOfflineAfterRentEnd(string calldata machineId) external onlyRentContract {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        machineId2Rented[machineId] = false;
        if (stakeInfo.isRentedByUser) {
            stakeInfo.isRentedByUser = false;
        }
        // 停止奖励（机器已离线）
        _stopRewarding(machineId, false);
        delete machineId2BeneficiaryInfos[machineId];
        emit EndRentMachine(stakeInfo.holder, machineId, 0);
    }

    function reportMachineFault(string calldata machineId, address renter) public onlyRentContract {
        if (!rewardStart()) {
            return;
        }

        if (renter == address(0)) {
            // if renter is not set, it means the machine is not rented by user
            // so we don't need to slash
            return;
        }
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        emit ReportMachineFault(machineId, renter);
        tryPaySlashOnReport(stakeInfo, machineId, renter);

        // 清理租赁状态（Rent 合约会同时清理自己的状态）
        machineId2Rented[machineId] = false;
        stakeInfo.isRentedByUser = false;
        delete machineId2BeneficiaryInfos[machineId];

        _claim(machineId);
        _unStake(machineId, stakeInfo.holder);
    }

    /// @notice 轻量惩罚：扣DLC罚金 + 结束租赁，但不解除NFT/DLC质押，不下架机器
    /// @dev 惩罚后机器保留在质押状态和白名单中，上线后自动可租
    ///      与 reportMachineFault 的区别：不调用 _unStake()，机器继续参与挖矿
    function reportMachineFaultLight(string calldata machineId, address renter) public onlyRentContract nonReentrant {
        if (!rewardStart()) {
            return;
        }

        if (renter == address(0)) {
            return;
        }

        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        // H-1: 验证机器确实已质押，未质押的机器不处理
        if (stakeInfo.holder == address(0)) {
            return;
        }

        // 1. 清理租赁状态（状态变更在外部调用之前，防止重入）
        machineId2Rented[machineId] = false;
        stakeInfo.isRentedByUser = false;
        delete machineId2BeneficiaryInfos[machineId];

        // 2. 先扣DLC罚金（M-1: slash 在 claim 之前，防止矿工先拿奖励再被扣不足）
        tryPaySlashOnReport(stakeInfo, machineId, renter);

        // 3. claim 未领奖励（slash 后再领，确保罚金优先）
        _claim(machineId);

        // 4. 设置冷却期（与 endRentMachine 一致，300秒）
        // C-1: 防止 endAtTimestamp < 1 hours 时下溢回滚
        stakeInfo.nextRenterCanRentAt = 300 + block.timestamp;
        if (stakeInfo.endAtTimestamp > 1 hours && block.timestamp > stakeInfo.endAtTimestamp - 1 hours) {
            stakeInfo.nextRenterCanRentAt = 0;
        }

        // 5. 恢复挖矿算力（不解除质押，机器继续参与挖矿）
        // C-2: try/catch 防止 dbcAI 合约异常阻塞整个惩罚链
        if (stakeInfo.nftCount > 0) {
            try dbcAIContract.getMachineInfo(machineId, true) returns (
                address, uint256 calcPoint, uint256, string memory, uint256, string memory, uint256, string memory, uint256
            ) {
                calcPoint = calcPoint * getNFTCount(stakeInfo.tokenIdBalances);
                _joinStaking(machineId, calcPoint, stakeInfo.reservedAmount);
            } catch {
                // dbcAI 合约异常（暂停/机器注销），跳过恢复算力
                // 机器不参与挖矿直到下次正常 _joinStaking
            }
        }

        emit ReportMachineFaultLight(machineId, renter, stakeInfo.nextRenterCanRentAt);
    }

    function tryPaySlashOnReport(StakeInfo storage stakeInfo, string memory machineId, address renter) internal {
        if (stakeInfo.reservedAmount >= SLASH_AMOUNT) {
            payToRenterForSlashing(machineId, stakeInfo, renter, true);
        } else {
            pendingSlashedMachineId2Renter[machineId].push(ApprovedReportInfo({renter: renter}));
        }
    }

    /// @notice 强制清理租赁状态（当 Rent 合约无记录但 isRentedByUser 仍为 true 时使用）
    /// @dev 任何人可调用，但需要 Rent 合约确认该机器无租赁记录
    ///      对齐 endRentMachine 的完整清理逻辑：重置 nextRenterCanRentAt + 恢复挖矿算力
    function forceCleanupRentStatus(string calldata machineId) external {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.isRentedByUser == true, "not rented");
        require(!rentContract.isRented(machineId), "still rented in Rent contract");

        stakeInfo.isRentedByUser = false;
        machineId2Rented[machineId] = false;

        // 设置 5 分钟冷却期（与 endRentMachine 一致）
        stakeInfo.nextRenterCanRentAt = 300 + block.timestamp;
        if (block.timestamp > stakeInfo.endAtTimestamp - 1 hours) {
            stakeInfo.nextRenterCanRentAt = 0;
        }

        // 恢复挖矿算力（与 endRentMachine 一致）
        if (stakeInfo.nftCount > 0) {
            (, uint256 calcPoint,,,,,,,) = dbcAIContract.getMachineInfo(machineId, true);
            calcPoint = calcPoint * getNFTCount(stakeInfo.tokenIdBalances);
            _joinStaking(machineId, calcPoint, stakeInfo.reservedAmount);
        }

        delete machineId2BeneficiaryInfos[machineId];
        emit EndRentMachine(stakeInfo.holder, machineId, stakeInfo.nextRenterCanRentAt);
    }

    /// @notice 管理员修复 nextRenterCanRentAt（处理异常值 0 或过大导致 canRent=false）
    function fixNextRenterCanRentAt(string calldata machineId, uint256 value) external onlyOwner {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.holder != address(0), "no stake info");
        stakeInfo.nextRenterCanRentAt = value;
    }

    function isStakingButOffline(string calldata machineId) external view returns (bool) {
        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
        return stakeInfo.calcPoint == 0 && stakeInfo.nftCount > 0;
    }

    function getaCalcPoint(string memory machineId) external view returns (uint256) {
        StakeInfo memory info = machineId2StakeInfos[machineId];
        return info.calcPoint;
    }

    function getMachineInfo(string memory machineId)
        external
        view
        returns (
            address holder,
            uint256 calcPoint,
            uint256 startAtTimestamp,
            uint256 endAtTimestamp,
            uint256 nextRenterCanRentAt,
            uint256 reservedAmount,
            bool isOnline,
            bool isRegistered
        )
    {
        StakeInfo memory info = machineId2StakeInfos[machineId];
        (bool _isOnline, bool _isRegistered) = dbcAIContract.getMachineState(machineId, PROJECT_NAME, STAKING_TYPE);
        return (
            info.holder,
            info.calcPoint,
            info.startAtTimestamp,
            info.endAtTimestamp,
            info.nextRenterCanRentAt,
            info.reservedAmount,
            _isOnline,
            _isRegistered
        );
    }

    function payToRenterForSlashing(
        string memory machineId,
        StakeInfo storage stakeInfo,
        address renter,
        bool alreadyStaked
    ) internal {
        SafeERC20.safeTransfer(rewardToken, renter, SLASH_AMOUNT);
        if (alreadyStaked) {
            _joinStaking(machineId, stakeInfo.calcPoint, stakeInfo.reservedAmount - SLASH_AMOUNT);
        }

        rentContract.paidSlash(machineId);
        emit PaySlash(machineId, renter, SLASH_AMOUNT);
    }

    function getGlobalState() external view returns (uint256, uint256, uint256) {
        return (totalCalcPoint, totalReservedAmount, rewardStartAtTimestamp + getRewardDuration());
    }

    function _getRewardDetail(uint256 totalRewardAmount)
        internal
        pure
        returns (uint256 canClaimAmount, uint256 lockedAmount)
    {
        uint256 releaseImmediateAmount = totalRewardAmount / 10;
        uint256 releaseLinearLockedAmount = totalRewardAmount - releaseImmediateAmount;
        return (releaseImmediateAmount, releaseLinearLockedAmount);
    }

    function getReward(string memory machineId) external view returns (uint256) {
        return calculateRewards(machineId);
    }

    function getDailyRewardAmount() public view returns (uint256) {
        return dailyRewardAmount;
    }

    function rewardStart() internal view returns (bool) {
        return rewardStartAtTimestamp > 0 && block.timestamp >= rewardStartAtTimestamp;
    }

    function _updateRewardPerCalcPoint() internal {
        uint256 accumulatedPerShareBefore = rewardsPerCalcPoint.accumulatedPerShare;
        rewardsPerCalcPoint = _getUpdatedRewardPerCalcPoint();
        emit RewardsPerCalcPointUpdate(accumulatedPerShareBefore, rewardsPerCalcPoint.accumulatedPerShare);
    }

    function _getUpdatedRewardPerCalcPoint() internal view returns (RewardCalculatorLib.RewardsPerShare memory) {
        uint256 rewardsPerSeconds = (getDailyRewardAmount()) / 1 days;
        if (rewardStartAtTimestamp == 0) {
            return RewardCalculatorLib.RewardsPerShare(0, 0);
        }
        uint256 rewardEndAt = rewardStartAtTimestamp + getRewardDuration();

        RewardCalculatorLib.RewardsPerShare memory rewardsPerTokenUpdated = RewardCalculatorLib.getUpdateRewardsPerShare(
            rewardsPerCalcPoint, totalAdjustUnit, rewardsPerSeconds, rewardStartAtTimestamp, rewardEndAt
        );
        return rewardsPerTokenUpdated;
    }

    function _updateMachineRewards(string memory machineId, uint256 machineShares) internal {
        _updateRewardPerCalcPoint();

        RewardCalculatorLib.UserRewards memory machineRewards = machineId2StakeUnitRewards[machineId];
        if (machineRewards.lastAccumulatedPerShare == 0) {
            machineRewards.lastAccumulatedPerShare = rewardsPerCalcPoint.accumulatedPerShare;
        }
        RewardCalculatorLib.UserRewards memory machineRewardsUpdated =
            RewardCalculatorLib.getUpdateUserRewards(machineRewards, machineShares, rewardsPerCalcPoint);
        machineId2StakeUnitRewards[machineId] = machineRewardsUpdated;
    }

    function _getMachineShares(uint256 calcPoint, uint256 reservedAmount) public pure returns (uint256) {
        return
            calcPoint * ToolLib.LnUint256(reservedAmount > BASE_RESERVE_AMOUNT ? reservedAmount : BASE_RESERVE_AMOUNT);
    }

    function _stopRewarding(string memory machineId, bool isBlocking) internal {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        _joinStaking(machineId, 0, stakeInfo.reservedAmount);
        //        stakeInfo.calcPoint = 0;
        if (isBlocking) {
            emit ExitStakingForBlocking(machineId, stakeInfo.holder);
        }else{
            emit ExitStakingForOffline(machineId, stakeInfo.holder);
        }
    }

    function stopRewarding(string memory machineId) external onlyRentAddress {
        _stopRewarding(machineId, false);
    }

    function _recoverRewarding(string memory machineId, bool isBlocking) internal {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        if (stakeInfo.calcPoint != 0) {
            return;
        }

        (, uint256 calcPoint,,,,,,,) = dbcAIContract.getMachineInfo(machineId, true);
        calcPoint = calcPoint * stakeInfo.nftCount;
        _joinStaking(machineId, calcPoint, stakeInfo.reservedAmount);
        if (isBlocking) {
            emit RecoverRewardingForBlocking(machineId, stakeInfo.holder);
        }else{
            emit RecoverRewarding(machineId, stakeInfo.holder);
        }
    }

    function recoverRewarding(string memory machineId) public onlyRentAddress {
        _recoverRewarding(machineId,false);
    }

    function _joinStaking(string memory machineId, uint256 calcPoint, uint256 reserveAmount) internal {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        uint256 oldLnReserved = ToolLib.LnUint256(
            stakeInfo.reservedAmount > BASE_RESERVE_AMOUNT ? stakeInfo.reservedAmount : BASE_RESERVE_AMOUNT
        );

        uint256 machineShares = stakeInfo.calcPoint * oldLnReserved;

        uint256 newLnReserved =
            ToolLib.LnUint256(reserveAmount > BASE_RESERVE_AMOUNT ? reserveAmount : BASE_RESERVE_AMOUNT);

        // Safe subtraction to prevent underflow (can happen after forceCleanupStakeInfo adjusts globals)
        uint256 oldShares = stakeInfo.calcPoint * oldLnReserved;
        totalAdjustUnit = totalAdjustUnit > oldShares ? totalAdjustUnit - oldShares : 0;
        totalAdjustUnit += calcPoint * newLnReserved;

        // update machine rewards
        _updateMachineRewards(machineId, machineShares);

        totalCalcPoint = totalCalcPoint > stakeInfo.calcPoint
            ? totalCalcPoint - stakeInfo.calcPoint + calcPoint
            : calcPoint;

        stakeInfo.calcPoint = calcPoint;
        if (reserveAmount > stakeInfo.reservedAmount) {
            SafeERC20.safeTransferFrom(
                rewardToken, stakeInfo.holder, address(this), reserveAmount - stakeInfo.reservedAmount
            );
        }
        if (reserveAmount != stakeInfo.reservedAmount) {
            if (reserveAmount >= stakeInfo.reservedAmount) {
                totalReservedAmount = totalReservedAmount + reserveAmount - stakeInfo.reservedAmount;
            } else {
                uint256 diff = stakeInfo.reservedAmount - reserveAmount;
                totalReservedAmount = totalReservedAmount > diff ? totalReservedAmount - diff : 0;
            }
            stakeInfo.reservedAmount = reserveAmount;
        }
    }

    function calculateRewards(string memory machineId) public view returns (uint256) {
        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
        if (stakeInfo.lastClaimAtTimestamp > stakeInfo.endAtTimestamp && stakeInfo.endAtTimestamp > 0) {
            return 0;
        }
        uint256 machineShares = _getMachineShares(stakeInfo.calcPoint, stakeInfo.reservedAmount);

        RewardCalculatorLib.UserRewards memory machineRewards = machineId2StakeUnitRewards[machineId];

        RewardCalculatorLib.RewardsPerShare memory currentRewardPerCalcPoint = _getUpdatedRewardPerCalcPoint();
        uint256 v = machineRewards.lastAccumulatedPerShare;
        if (machineRewards.lastAccumulatedPerShare == 0) {
            if (stakeInfo.startAtTimestamp < rewardStartAtTimestamp && stakeInfo.claimedAmount == 0) {
                v = rewardPerShareAtRewardStart;
            } else {
                v = rewardsPerCalcPoint.accumulatedPerShare;
            }
        }
        uint256 rewardAmount = RewardCalculatorLib.calculatePendingUserRewards(
            machineShares, v, currentRewardPerCalcPoint.accumulatedPerShare
        );

        return machineRewards.accumulated + rewardAmount;
    }

    function rewardEnd() public view returns (bool) {
        if (rewardStartAtTimestamp == 0) {
            return false;
        }
        return (block.timestamp > rewardStartAtTimestamp + getRewardDuration());
    }

    function getRewardEndAtTimestamp(uint256 stakeEndAtTimestamp) internal view returns (uint256) {
        uint256 rewardEndAt = rewardStartAtTimestamp + getRewardDuration();
        uint256 currentTime = block.timestamp;
        if (stakeEndAtTimestamp > rewardEndAt) {
            return rewardEndAt;
        } else if (stakeEndAtTimestamp > currentTime && stakeEndAtTimestamp - currentTime <= 1 hours) {
            return stakeEndAtTimestamp > 1 hours ? stakeEndAtTimestamp - 1 hours : 0;
        }
        if (stakeEndAtTimestamp != 0 && stakeEndAtTimestamp < currentTime) {
            return stakeEndAtTimestamp;
        }
        return currentTime;
    }

    function getRewardStartTime(uint256 _rewardStartAtTimestamp) public view returns (uint256) {
        if (_rewardStartAtTimestamp == 0) {
            return 0;
        }
        if (block.timestamp > _rewardStartAtTimestamp) {
            uint256 timeDuration = block.timestamp - _rewardStartAtTimestamp;
            return block.timestamp - timeDuration;
        }

        return block.timestamp + (_rewardStartAtTimestamp - block.timestamp);
    }

    //    function claimDLC() external onlyOwner {
    //        rewardToken.transfer(owner(), 3_960_000 ether);
    //    }

    function version() external pure returns (uint256) {
        return 11;
    }

    function oneDayAccumulatedPerShare(uint256 currentAccumulatedPerShare, uint256 totalShares)
        internal
        view
        returns (uint256)
    {
        uint256 elapsed = 1 days;
        uint256 rewardsRate = (getDailyRewardAmount()) / 1 days;

        uint256 accumulatedPerShare = currentAccumulatedPerShare + 1 ether * elapsed * rewardsRate / totalShares;

        return accumulatedPerShare;
    }

    function preCalculateRewards(uint256 calcPoint, uint256 nftCount, uint256 reserveAmount)
        public
        view
        returns (uint256)
    {
        calcPoint = calcPoint * nftCount;
        uint256 machineShares = _getMachineShares(calcPoint, reserveAmount);
        uint256 machineAccumulatedPerShare = rewardsPerCalcPoint.accumulatedPerShare;

        uint256 totalShares = totalAdjustUnit + machineShares;

        uint256 _oneDayAccumulatedPerShare = oneDayAccumulatedPerShare(machineAccumulatedPerShare, totalShares);

        uint256 rewardAmount = RewardCalculatorLib.calculatePendingUserRewards(
            machineShares, machineAccumulatedPerShare, _oneDayAccumulatedPerShare
        );

        return rewardAmount;
    }

    function setGlobalConfig(uint256 platformFeeRate_, BeneficiaryInfo[] calldata globalBeneficiaryInfos_)
        external
        onlyDLCClientWallet
        isValidConfigs(globalBeneficiaryInfos_)
    {
        require(platformFeeRate_ < 100, "platformFeeRate should be less than 100");
        platformFeeRate = platformFeeRate_;
        globalBeneficiaryInfos = globalBeneficiaryInfos_;
    }

    function setMachineConfig(string calldata machineId, BeneficiaryInfo[] calldata machineBeneficiaryInfos_)
        external
        onlyDLCClientWallet
        isValidConfigs(machineBeneficiaryInfos_)
    {
        machineId2BeneficiaryInfos[machineId] = machineBeneficiaryInfos_;
    }

    function clearMachineConfig(string calldata machineId) external onlyDLCClientWallet {
        delete machineId2BeneficiaryInfos[machineId];
    }

    function getMachineConfig(string memory machineId)
        public
        view
        returns (address[] memory beneficiaries, uint256[] memory rates, uint256 _platformFeeRate)
    {
        BeneficiaryInfo[] memory beneficiaryInfos;
        if (machineId2BeneficiaryInfos[machineId].length > 0) {
            beneficiaryInfos = machineId2BeneficiaryInfos[machineId];
        } else {
            beneficiaryInfos = globalBeneficiaryInfos;
        }

        if (beneficiaryInfos.length == 0) {
            return (beneficiaries, rates, 0);
        }

        beneficiaries = new address[](beneficiaryInfos.length);
        rates = new uint256[](beneficiaryInfos.length);
        for (uint8 i = 0; i < beneficiaryInfos.length; i++) {
            beneficiaries[i] = beneficiaryInfos[i].beneficiary;
            rates[i] = beneficiaryInfos[i].rate;
        }
        return (beneficiaries, rates, platformFeeRate);
    }

    function isPersonalMachine(string memory machineId) external view returns (bool) {
        return machineId2Personal[machineId];
    }

    function setMachineToPersonal(string[] calldata machineIds) external onlyDLCClientWallet {
        for (uint256 i = 0; i < machineIds.length; i++) {
            machineId2Personal[machineIds[i]] = true;
        }
    }

    function updateMachineRegisterStatus(string memory machineId,bool registered) external onlyRentAddress {
        if (registered){
            emit MachineRegistered(machineId);
        }else{
            emit MachineUnregistered(machineId);
        }
    }
}

// src/rent/Rent.sol

/// @custom:oz-upgrades-from OldRent
contract Rent is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    uint8 public constant SECONDS_PER_BLOCK = 6;
    uint256 public constant REPORT_RESERVE_AMOUNT = 10_000 ether;
    uint256 public constant SLASH_AMOUNT = 10_000 ether;
    uint256 public constant ONE_CALC_POINT_USD_VALUE_PER_MONTH = 5_080;
    uint256 public constant FACTOR = 10_000;
    uint256 public constant USD_DECIMALS = 1_000_000;

    IRewardToken public feeToken;
    IPrecompileContract public precompileContract;
    IStakingContract public stakingContract;
    IDBCAIContract public dbcAIContract;

    address public canUpgradeAddress;
    uint256 public lastRentId;
    uint256 public totalBurnedAmount;
    uint8 public voteThreshold;
    bool public registered;
    RentGPUInfo public rentGPUInfo;

    enum SlashType {
        Offline,
        RenterReport
    }

    enum NotifyType {
        ContractRegister,
        MachineRegister,
        MachineUnregister,
        MachineOnline,
        MachineOffline
    }

    enum Vote {
        None,
        Yes,
        No,
        Finished
    }

    struct RentInfo {
        address stakeHolder;
        string machineId;
        uint256 rentStatTime;
        uint256 rentEndTime;
        address renter;
    }

    struct BurnedDetail {
        uint256 rentId;
        uint256 burnTime;
        uint256 burnDLCAmount;
        address renter;
    }

    struct BurnedInfo {
        BurnedDetail[] details;
        uint256 totalBurnedAmount;
    }

    struct SlashInfo {
        address stakeHolder;
        string machineId;
        uint256 slashAmount;
        uint256 rentStartAtTimestamp;
        uint256 rentEndAtTimestamp;
        uint256 rentedDurationSeconds;
        address renter;
        SlashType slashType;
        uint256 createdAt;
        bool paid;
    }

    struct RentGPUInfo {
        uint256 rentedGPUCount;
        uint256 rentingGPUCount;
    }

    address[] public adminsToApprove;
    string[] public pendingSlashMachineIds;

    mapping(uint256 => RentInfo) public rentId2RentInfo;
    mapping(string => uint256) public machineId2RentId;
    mapping(address => uint256[]) public renter2RentIds;
    mapping(string => BurnedInfo) public machineId2BurnedInfo;
    mapping(string => SlashInfo) public machineId2SlashInfo;
    mapping(string => mapping(address => Vote)) public pendingSlashMachineId2ApprovedAdmins;
    mapping(string => uint8) public pendingSlashMachineId2ApprovedCount;
    mapping(string => uint8) public pendingSlashMachineId2RefuseCount;
    mapping(address => uint256) public stakeHolder2RentFee;
    mapping(address => RentGPUInfo) public stakeHolder2RentGPUInfo;
    mapping(string => uint256) public machineId2LastRentEndBlock;
    mapping(string => SlashInfo[]) public machineId2SlashInfos;

    struct FeeInfo {
        uint256 baseFee;
        uint256 extraFee;
        uint256 platformFee;
        bool isV1;  // true: extraFee 是 DLC (V1); false: extraFee 是 Point Token (V2，默认值，兼容旧数据)
    }

    IOracle public oracle;
    mapping(uint256 => FeeInfo) public rentId2FeeInfoInDLC;
    mapping(string => bool) public rentWhitelist;
    mapping(address => bool) public adminsToSetRentWhiteList;
    mapping(string => bool) public machine2ProxyRented;
    mapping(string => address) public machine2ProxyRentPayer;
    struct TokenPriceInfo{
        uint256 price;
        uint256 timestamp;
    }
    TokenPriceInfo public tokenPriceInfo;

    // v5: monthly rental flag — skip slash on offline, endRent clears it
    mapping(string => bool) public machineId2IsMonthlyRent;

    // v6: unpaid slash counter — O(1) check instead of O(n) array scan
    mapping(string => uint256) public machineId2UnpaidSlashCount;

    // v7: last slash timestamp — O(1) query for last penalty time
    mapping(string => uint256) public machineId2LastSlashTimestamp;

    // v8: rent whitelist counter — total number of machines in rent whitelist
    uint256 public rentWhitelistCount;

    event RentMachine(
        address indexed machineOnwer,
        uint256 rentId,
        string machineId,
        uint256 rentEndTime,
        address renter,
        uint256 rentFee
    );
    event EndRentMachine(
        address machineOnwer, 
        uint256 rentId, 
        string machineId, 
        uint256 rentEndTime, 
        address renter
    );

    event RenewRent(
        address indexed machineOnwer,
        string machineId,
        uint256 rentId,
        uint256 additionalRentSeconds,
        uint256 additionalRentFee,
        address renter
    );
    event ExtraRentFeeTransfer(address indexed machineOnwer, uint256 rentId, uint256 amount);
    event ReportMachineFault(uint256 rentId, string machineId, address reporter);
    event BurnedFee(
        string machineId, uint256 rentId, uint256 burnTime, uint256 burnDLCAmount, address renter, uint8 rentGpuCount
    );
    event PayBackFee(string machineId, uint256 rentId, address renter, uint256 amount);
    event PayBackExtraFee(string machineId, uint256 rentId, address renter, uint256 amount);
    event PayBackExtraFeeShortfall(string machineId, uint256 rentId, address renter, uint256 owed, uint256 actual);
    event PayBackPointFee(string machineId, uint256 rentId, address renter, uint256 amount);
    event RentTime(uint256 totalRentSenconds, uint256 usedRentSeconds);
    event PayToContractOnRent(uint256 rentId, address renter, uint256 totalRentFee);
    event RentFee(uint256 rentId, address renter, uint256 baseRentFee, uint256 extraRentFee, uint256 platformFee);

    event RenterPayExtraRentFee(uint256 rentId, address renter, uint256 amount);
    event ApprovedReport(string machineId, address admin);
    event RefusedReport(string machineId, address admin);
    event ExecuteReport(string machineId, Vote vote);
    event MachineRegister(string machineId, uint256 calcPoint);
    event MachineUnregister(string machineId, uint256 calcPoint);
    event PaidSlash(string machineId);
    event SlashMachineOnOffline(
        address indexed stakeHolder,
        string machineId,
        address indexed renter,
        uint256 slashAmount,
        uint256 rentStartAt,
        uint256 rentEndAt,
        SlashType slashType
    );
    event RemoveCalcPointOnOffline(string machineId);
    event AddCalcPointOnline(string machineId);

    event AddBackCalcPointOnOnline(string machineId, uint256 calcPoint);
    event PlatformFeeTransfer(address indexed machineOnwer, uint256 rentId, uint256 amount);
    event TokenPriceUpdated(uint256 oldPrice, uint256 newPrice, uint256 timestamp);

    error NotApproveAdmin();
    error ZeroCalcPoint();
    error CallerNotStakingContract();
    error ZeroAddress();
    error CanNotUpgrade(address);
    error CountOfApproveAdminsShouldBeFive();
    error ElementNotFound();
    error uint256Overflow();
    error InvalidRentDuration(uint256 rentDuration);
    error MachineCanNotRent();
    error RentDurationTooLong(uint256 rentDuration, uint256 maxRentDuration);
    error RenTimeCannotOverMachineUnstakeTime();
    error MachineCanNotRentWithin100BlocksAfterLastRent();
    error BalanceNotEnough();
    error PointNotEnough();
    error RentEnd();
    error RentNotEnd();
    error NotRenter();
    error RentingNotExist();
    error MachineNotRented();
    error ReserveAmountForReportShouldBe10000();
    error ReportedMachineNotFound();
    error VoteFinished();
    error NotDBCAIContract();
    error RewardNotStart();
    error NotValidMachineId();
    error RenterAndPayerIsSame();
    error ProxyRentCanNotEndByRenter();
    error NotProxyRentingMachine();
    error NoUnpaidSlash();

    event SlashPaidByStakeHolder(string machineId, address stakeHolder, address renter, uint256 amount);

    modifier onlyApproveAdmins() {
        bool found = false;
        for (uint8 i = 0; i < adminsToApprove.length; i++) {
            if (msg.sender == adminsToApprove[i]) {
                found = true;
                break;
            }
        }
        require(found, NotApproveAdmin());
        _;
    }

    modifier onlyStakingContract() {
        require(msg.sender == address(stakingContract), CallerNotStakingContract());
        _;
    }

    modifier onlyDBCAIContract() {
        require(msg.sender == address(dbcAIContract), NotDBCAIContract());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _initialOwner,
        address _precompileContract,
        address _stakingContract,
        address _dbcAIContract,
        address _feeToken
    ) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        feeToken = IRewardToken(_feeToken);
        precompileContract = IPrecompileContract(_precompileContract);
        stakingContract = IStakingContract(_stakingContract);
        dbcAIContract = IDBCAIContract(_dbcAIContract);
        voteThreshold = 3;
        canUpgradeAddress = msg.sender;
    }

    /// @notice Reinitialize function for upgrading from previous versions
    /// @dev This function should be called after upgrading to initialize ReentrancyGuard
    function reinitialize() public reinitializer(2) {
        __ReentrancyGuard_init();
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        require(newImplementation != address(0), ZeroAddress());
        require(msg.sender == canUpgradeAddress, CanNotUpgrade(msg.sender));
    }

    function setCanUpgradeAddress(address addr) external onlyOwner {
        require(addr != address(0), ZeroAddress());
        canUpgradeAddress = addr;
    }

    function setDBCAIContract(address addr) external onlyOwner {
        require(addr != address(0), ZeroAddress());
        dbcAIContract = IDBCAIContract(addr);
    }

    function setOracle(address addr) external onlyOwner {
        require(addr != address(0), ZeroAddress());
        oracle = IOracle(addr);
    }

    function setAdminsToApproveMachineFaultReporting(address[] calldata admins) external onlyOwner {
        require(admins.length == 5, CountOfApproveAdminsShouldBeFive());
        adminsToApprove = admins;
    }

    function setFeeToken(address _feeToken) external onlyOwner {
        require(_feeToken != address(0x0), ZeroAddress());
        feeToken = IRewardToken(_feeToken);
    }

    function setStakingContract(address addr) external onlyOwner {
        require(addr != address(0), ZeroAddress());
        stakingContract = IStakingContract(addr);
    }

    function setPrecompileContract(address _precompileContract) external onlyOwner {
        require(_precompileContract != address(0x0), ZeroAddress());
        precompileContract = IPrecompileContract(_precompileContract);
    }

    function findUintIndex(uint256[] memory arr, uint256 v) internal pure returns (uint256) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == v) {
                return i;
            }
        }
        revert ElementNotFound();
    }

    function removeValueOfUintArray(uint256 v, uint256[] storage arr) internal {
        uint256 index = findUintIndex(arr, v);
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    function findStringIndex(string[] memory arr, string memory v) internal pure returns (uint256) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (keccak256(abi.encodePacked(arr[i])) == keccak256(abi.encodePacked(v))) {
                return i;
            }
        }
        revert ElementNotFound();
    }

    function removeValueOfStringArray(string memory addr, string[] storage arr) internal {
        uint256 index = findStringIndex(arr, addr);
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    function getNextRentId() internal returns (uint256) {
        require(lastRentId < type(uint256).max, uint256Overflow());
        lastRentId += 1;
        return lastRentId;
    }

    function resonFoCanNotRent(string calldata machineId) public view returns (string memory reson) {
        if (!inRentWhiteList(machineId)) {
            return "not in rent whitelist";
        }
        if (isRented(machineId)) {
            return "is rented";
        }
        if (!stakingContract.isStaking(machineId)) {
            return "not in staking";
        }

        if (stakingContract.machineIsBlocked(machineId)) {
            return "is blocked(in blacklist)";
        }

        if (stakingContract.isStakingButOffline(machineId)) {
            return "is staking but offline";
        }

        (,, uint256 rewardEndAt) = stakingContract.getGlobalState();
        if (rewardEndAt == stakingContract.getRewardDuration() || rewardEndAt < block.timestamp) {
            return "not enough staking duration";
        }

        (, ,, uint256 endAtTimestamp, uint256 nextRenterCanRentAt,, bool isOnline, bool isRegistered) =
            stakingContract.getMachineInfo(machineId);
    
        if (!isOnline){
            return "is offline";
        }
        if (!isRegistered){
            return "not registered";
        }

        if (nextRenterCanRentAt > block.timestamp || nextRenterCanRentAt == 0) {
            // not reach the start rent block number yet
            return "can not rent before next renter can rent time";
        }
        if (endAtTimestamp > 0) {
            if (!(endAtTimestamp > block.timestamp && endAtTimestamp - block.timestamp > 1 hours)){
                return "machine staking time less than 1 hours";
            }
        }

        return "";
    }

    function canRent(string calldata machineId) public view returns (bool) {
        if (!inRentWhiteList(machineId)) {
            return false;
        }
        if (isRented(machineId)) {
            return false;
        }
        if (!stakingContract.isStaking(machineId)) {
            return false;
        }

        if (stakingContract.machineIsBlocked(machineId)) {
            return false;
        }

        if (stakingContract.isStakingButOffline(machineId)) {
            return false;
        }

        (,, uint256 rewardEndAt) = stakingContract.getGlobalState();
        if (rewardEndAt == stakingContract.getRewardDuration()) {
            return false;
        }
        if (rewardEndAt < block.timestamp) {
            return false;
        }

        (,,, uint256 endAtTimestamp, uint256 nextRenterCanRentAt,, bool isOnline, bool isRegistered) =
            stakingContract.getMachineInfo(machineId);
        if (!isOnline || !isRegistered) {
            return false;
        }

        if (nextRenterCanRentAt > block.timestamp || nextRenterCanRentAt == 0) {
            // not reach the start rent block number yet
            return false;
        }
        if (endAtTimestamp > 0) {
            return endAtTimestamp > block.timestamp && endAtTimestamp - block.timestamp > 1 hours;
        }

        return endAtTimestamp == 0;
    }

    function getMachineInfo(string memory machineId)
        public
        view
        returns (uint256 availableRentHours, uint256 reservedAmount, uint256 rentFeePerHour)
    {
        (,,, uint256 endAt,, uint256 _reservedAmount,,) = stakingContract.getMachineInfo(machineId);
        uint256 rentFee = getMachinePrice(machineId, 1 hours / SECONDS_PER_BLOCK);
        if (isRented(machineId)) {
            return (0, _reservedAmount, rentFee);
        }

        return ((endAt - block.timestamp) / 1 hours, _reservedAmount, rentFee);
    }

    function getMachinePrice(string memory machineId, uint256 rentSeconds) public view returns (uint256){
        uint256 baseMachinePrice = getBaseMachinePrice(machineId, rentSeconds);
        uint256 extraRentFee = getExtraRentFee(machineId, rentSeconds);
        (,, uint256 platformFeeRate) = stakingContract.getMachineConfig(machineId);
        uint256 platformFee = (baseMachinePrice + extraRentFee) * platformFeeRate / 100;
        uint256 totalFee = baseMachinePrice + extraRentFee + platformFee;
        return totalFee;
    }

    function getMachinePriceV2(string memory machineId, uint256 rentSeconds) public view returns (uint256){
        uint256 baseMachinePrice = getBaseMachinePrice(machineId, rentSeconds);
        uint256 extraRentFee = getExtraRentFee(machineId, rentSeconds);
        (,, uint256 platformFeeRate) = stakingContract.getMachineConfig(machineId);
        uint256 platformFee = (baseMachinePrice + extraRentFee) * platformFeeRate / 100;
        uint256 totalFee = baseMachinePrice + platformFee;
        return totalFee;
    }

    function getMachinePriceInUSD(string memory machineId, uint256 rentSeconds) public view returns  ( uint256 totalFee, uint256 baseMachinePrice, uint256 extraRentFee, uint256 platformFee) {
        baseMachinePrice = getBaseMachinePriceInUSD(machineId, rentSeconds);
        extraRentFee = getExtraRentFeeInUSD(machineId, rentSeconds);
        (,, uint256 platformFeeRate) = stakingContract.getMachineConfig(machineId);
        platformFee = (baseMachinePrice + extraRentFee) * platformFeeRate / 100;
        totalFee = baseMachinePrice + extraRentFee + platformFee;
        return (totalFee, baseMachinePrice, extraRentFee, platformFee);
    }

    function getBaseMachinePriceInUSD(string memory machineId, uint256 rentSeconds) public view returns (uint256) {
        (, uint256 calcPointInFact,,,,,,,) = dbcAIContract.getMachineInfo(machineId, true);
        require(calcPointInFact > 0, ZeroCalcPoint());

        // calcPont factor : 10000 ; ONE_CALC_POINT_USD_VALUE_PER_MONTH factor: 10000
        uint256 totalFactor = FACTOR * FACTOR;

        uint256 rentFeeUSD = USD_DECIMALS * rentSeconds * calcPointInFact * ONE_CALC_POINT_USD_VALUE_PER_MONTH / 30 / 24
            / 60 / 60 / totalFactor;
        rentFeeUSD = rentFeeUSD * 6 / 10; // 60% of the total rent fee
        return rentFeeUSD;
    }

    function setTokenPriceInUSD(uint256 price) external  {
        require(price > 0, "invalid price");
        require(msg.sender == address(0xf050e9C7425A9f6F7496F5dd287F9A3575751Fc6), "has no permission");
        uint256 oldPrice = tokenPriceInfo.price;
        tokenPriceInfo.price = price;
        tokenPriceInfo.timestamp = block.timestamp;
        emit TokenPriceUpdated(oldPrice, price, block.timestamp);
    }

    function getTokenPrice() internal view returns (uint256) {
        if (tokenPriceInfo.timestamp > 0&& tokenPriceInfo.price > 0){
            return tokenPriceInfo.price;
        }
        return oracle.getTokenPriceInUSD(10, address(feeToken));
    }

    function getBaseMachinePrice(string memory machineId, uint256 rentSeconds) public view returns (uint256) {

        uint256 rentFeeUSD = getBaseMachinePriceInUSD(machineId,rentSeconds);
        uint256 dlcUSDPrice = getTokenPrice();

        uint256 baseRentFeeUSD = 1e18 * rentFeeUSD / dlcUSDPrice;
        return baseRentFeeUSD;
    }

    function getExtraRentFeeInUSD(string memory machineId, uint256 rentSeconds) public view returns (uint256) {
        uint256 rentMinutes = rentSeconds / 60;

        uint256 fee = stakingContract.getMachineExtraRentFee(machineId) * rentMinutes;
        if (fee == 0) {
            return 0;
        }

        return fee;
    }

    function getExtraRentFeeInPoint(string memory machineId, uint256 rentSeconds) public view returns (uint256) {
        // Reorder to avoid overflow: (feeUSD * 1e18 * 1000) / 1e6 = feeUSD * 1e15
        // But do division first to prevent overflow: feeUSD * 1e18 / 1e6 * 1000 = feeUSD * 1e15
        uint256 feeUSD = getExtraRentFeeInUSD(machineId, rentSeconds);
        return feeUSD * 1e15;
    }

    function getExtraRentFee(string memory machineId, uint256 rentSeconds) public view returns (uint256) {
        uint256 dlcUSDPrice = getTokenPrice();
        uint256 fee = getExtraRentFeeInUSD(machineId, rentSeconds);
        uint256 baseRentFeeDLC = 1e18 * fee / dlcUSDPrice;
        return baseRentFeeDLC;
    }

    function inRentWhiteList(string calldata machineId) public view returns (bool) {
        if (stakingContract.isPersonalMachine(machineId)) {
            return true;
        }
        return rentWhitelist[machineId];
    }

    function setRentingWhitelist(string[] calldata machineIds, bool isAdd) external {
        require(adminsToSetRentWhiteList[msg.sender], "has no permission to set renting whitelist");
        for (uint256 i = 0; i < machineIds.length; i++) {
            bool current = rentWhitelist[machineIds[i]];
            if (current != isAdd) {
                rentWhitelist[machineIds[i]] = isAdd;
                if (isAdd) {
                    rentWhitelistCount++;
                } else {
                    if (rentWhitelistCount > 0) rentWhitelistCount--;
                }
            }
        }
    }

    function setAdminsToAddRentWhiteList(address[] calldata admins) external onlyOwner {
        for (uint256 i = 0; i < admins.length; i++) {
            adminsToSetRentWhiteList[admins[i]] = true;
        }
    }

    function rentMachine(string calldata machineId, uint256 rentSeconds) external {
        _rentMachine(msg.sender, msg.sender, machineId, rentSeconds);
    }

    function rentMachineV2(string calldata machineId, uint256 rentSeconds) external {
        _rentMachineV2(msg.sender, msg.sender, machineId, rentSeconds);
    }

    function rentProxyMachineV2(address renter, string calldata machineId, uint256 rentSeconds) external {
        require(msg.sender != renter, RenterAndPayerIsSame());
        _rentMachineV2(msg.sender, renter, machineId, rentSeconds);
    }

    function rentProxyMachineMonthly(address renter, string calldata machineId, uint256 pointAmount) external {
        require(adminsToSetRentWhiteList[msg.sender], "not monthly rent admin");
        require(msg.sender != renter, RenterAndPayerIsSame());
        _rentMachineMonthly(msg.sender, renter, machineId, pointAmount);
    }

    function rentProxyMachine(address renter, string calldata machineId, uint256 rentSeconds) external {
        require(msg.sender != renter, RenterAndPayerIsSame());
        _rentMachine(msg.sender, renter, machineId, rentSeconds);
    }

    function _rentMachine(address payer, address renter, string calldata machineId, uint256 rentSeconds) internal {
        require(inRentWhiteList(machineId), NotValidMachineId());
        require(rentSeconds >= 10 minutes && rentSeconds <= 10 hours, InvalidRentDuration(rentSeconds));
        require(canRent(machineId), MachineCanNotRent());

        (address machineHolder,,, uint256 endAtTimestamp,,,,) = stakingContract.getMachineInfo(machineId);
        require(block.timestamp + rentSeconds < endAtTimestamp, RenTimeCannotOverMachineUnstakeTime());
        uint256 rewardDuration = stakingContract.getRewardDuration();
        (,, uint256 rewardEndAt) = stakingContract.getGlobalState();
        require(rewardEndAt > rewardDuration, RewardNotStart());
        require(rewardEndAt > block.timestamp, RewardNotStart());
        uint256 maxRentDuration = Math.min(Math.min(endAtTimestamp, rewardEndAt) - block.timestamp, rewardDuration);
        require(rentSeconds <= maxRentDuration, RentDurationTooLong(rentSeconds, maxRentDuration));
        bool isProxyRent = msg.sender != renter;
        require(msg.sender == payer, "invalid payer");
        machine2ProxyRented[machineId] = isProxyRent;
        if (isProxyRent){
            machine2ProxyRentPayer[machineId] = payer;
        }

        uint256 lastRentEndBlock = machineId2LastRentEndBlock[machineId];
        if (lastRentEndBlock != 0) {
            require(block.number > lastRentEndBlock + 30, MachineCanNotRentWithin100BlocksAfterLastRent());
        }

        (,, uint256 platformFeeRate) = stakingContract.getMachineConfig(machineId);

        uint256 baseRentFee = getBaseMachinePrice(machineId, rentSeconds);
        uint256 extraRentFee = getExtraRentFee(machineId, rentSeconds);
        uint256 platformFee = (baseRentFee + extraRentFee) * platformFeeRate / 100;
        uint256 totalRentFee = baseRentFee + extraRentFee + platformFee;
        require(feeToken.balanceOf(payer) >= totalRentFee, BalanceNotEnough());

        uint256 _now = block.timestamp;

        // save rent info
        lastRentId = getNextRentId();
        rentId2RentInfo[lastRentId] = RentInfo({
            stakeHolder: machineHolder,
            machineId: machineId,
            rentStatTime: _now,
            rentEndTime: _now + rentSeconds,
            renter: renter
        });
        machineId2RentId[machineId] = lastRentId;
        renter2RentIds[renter].push(lastRentId);

        FeeInfo memory feeInfo;
        feeInfo.baseFee = baseRentFee;
        feeInfo.extraFee = extraRentFee;
        feeInfo.platformFee = platformFee;
        feeInfo.isV1 = true;  // V1: extraFee 是 DLC
        rentId2FeeInfoInDLC[lastRentId] = feeInfo;

        SafeERC20.safeTransferFrom(feeToken, payer, address(this), totalRentFee);
        emit RentFee(lastRentId, msg.sender, baseRentFee, extraRentFee, platformFee);
        emit PayToContractOnRent(lastRentId, msg.sender, totalRentFee);

        // notify staking contract renting machine action happened
        stakingContract.rentMachine(machineId);

        emit RentMachine(machineHolder, lastRentId, machineId, block.timestamp + rentSeconds, renter, baseRentFee);
    }

    function _rentMachineV2(address payer, address renter, string calldata machineId, uint256 rentSeconds) internal {
        require(inRentWhiteList(machineId), NotValidMachineId());
        require(rentSeconds >= 10 minutes && rentSeconds <= 10 hours, InvalidRentDuration(rentSeconds));
        require(canRent(machineId), MachineCanNotRent());

        (address machineHolder,,, uint256 endAtTimestamp,,,,) = stakingContract.getMachineInfo(machineId);
        require(block.timestamp + rentSeconds < endAtTimestamp, RenTimeCannotOverMachineUnstakeTime());
        uint256 rewardDuration = stakingContract.getRewardDuration();
        (,, uint256 rewardEndAt) = stakingContract.getGlobalState();
        require(rewardEndAt > rewardDuration, RewardNotStart());
        require(rewardEndAt > block.timestamp, RewardNotStart());
        uint256 maxRentDuration = Math.min(Math.min(endAtTimestamp, rewardEndAt) - block.timestamp, rewardDuration);
        require(rentSeconds <= maxRentDuration, RentDurationTooLong(rentSeconds, maxRentDuration));
        bool isProxyRent = msg.sender != renter;
        require(msg.sender == payer, "invalid payer");
        machine2ProxyRented[machineId] = isProxyRent;
        if (isProxyRent){
            machine2ProxyRentPayer[machineId] = payer;
        }

        uint256 lastRentEndBlock = machineId2LastRentEndBlock[machineId];
        if (lastRentEndBlock != 0) {
            require(block.number > lastRentEndBlock + 30, MachineCanNotRentWithin100BlocksAfterLastRent());
        }

        (,, uint256 platformFeeRate) = stakingContract.getMachineConfig(machineId);

        uint256 baseRentFee = getBaseMachinePrice(machineId, rentSeconds);
        uint256 extraRentFee = getExtraRentFee(machineId, rentSeconds);
        uint256 extraRentFeeInPoint = getExtraRentFeeInPoint(machineId, rentSeconds);

        uint256 platformFee = (baseRentFee + extraRentFee) * platformFeeRate / 100;
        uint256 totalRentFee = baseRentFee + platformFee;
        require(feeToken.balanceOf(payer) >= totalRentFee, BalanceNotEnough());
        IERC20 pointToken = IERC20(address(0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6));
        require(pointToken.balanceOf(payer) >= extraRentFeeInPoint, PointNotEnough());

        uint256 _now = block.timestamp;

        // save rent info
        lastRentId = getNextRentId();
        rentId2RentInfo[lastRentId] = RentInfo({
            stakeHolder: machineHolder,
            machineId: machineId,
            rentStatTime: _now,
            rentEndTime: _now + rentSeconds,
            renter: renter
        });
        machineId2RentId[machineId] = lastRentId;
        renter2RentIds[renter].push(lastRentId);

        FeeInfo memory feeInfo;
        feeInfo.baseFee = baseRentFee;
        feeInfo.extraFee = extraRentFeeInPoint;
        feeInfo.platformFee = platformFee;
        // feeInfo.isV1 默认为 false，表示 V2: extraFee 是 Point Token
        rentId2FeeInfoInDLC[lastRentId] = feeInfo;

        SafeERC20.safeTransferFrom(feeToken, payer, address(this), totalRentFee);
        SafeERC20.safeTransferFrom(pointToken, payer, address(this), extraRentFeeInPoint);

        emit RentFee(lastRentId, msg.sender, baseRentFee, extraRentFee, platformFee);
        emit PayToContractOnRent(lastRentId, msg.sender, totalRentFee);

        // notify staking contract renting machine action happened
        stakingContract.rentMachine(machineId);

        emit RentMachine(machineHolder, lastRentId, machineId, block.timestamp + rentSeconds, renter, baseRentFee);
    }

    function _rentMachineMonthly(address payer, address renter, string calldata machineId, uint256 pointAmount) internal {
        uint256 rentSeconds = 30 days;
        require(inRentWhiteList(machineId), NotValidMachineId());
        require(canRent(machineId), MachineCanNotRent());

        (address machineHolder,,, uint256 endAtTimestamp,,,,) = stakingContract.getMachineInfo(machineId);
        require(block.timestamp + rentSeconds < endAtTimestamp, RenTimeCannotOverMachineUnstakeTime());

        require(msg.sender == payer, "invalid payer");
        machine2ProxyRented[machineId] = true;
        machine2ProxyRentPayer[machineId] = payer;
        machineId2IsMonthlyRent[machineId] = true;

        uint256 lastRentEndBlock = machineId2LastRentEndBlock[machineId];
        if (lastRentEndBlock != 0) {
            require(block.number > lastRentEndBlock + 30, MachineCanNotRentWithin100BlocksAfterLastRent());
        }

        uint256 _now = block.timestamp;

        lastRentId = getNextRentId();
        rentId2RentInfo[lastRentId] = RentInfo({
            stakeHolder: machineHolder,
            machineId: machineId,
            rentStatTime: _now,
            rentEndTime: _now + rentSeconds,
            renter: renter
        });
        machineId2RentId[machineId] = lastRentId;
        renter2RentIds[renter].push(lastRentId);

        // Monthly rental: platform deposits miner's share (5/6 of user payment) as Point tokens
        // baseFee=0 (no DLC burn), platformFee=0, extraFee=pointAmount (Point → machineHolder on endRent)
        // isV1=false by default → endRentMachine V2 path handles Point distribution correctly
        FeeInfo memory feeInfo;
        feeInfo.extraFee = pointAmount;
        rentId2FeeInfoInDLC[lastRentId] = feeInfo;

        if (pointAmount > 0) {
            IERC20 pointToken = IERC20(address(0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6));
            SafeERC20.safeTransferFrom(pointToken, payer, address(this), pointAmount);
        }

        // notify staking contract
        stakingContract.rentMachine(machineId);

        emit RentMachine(machineHolder, lastRentId, machineId, _now + rentSeconds, renter, 0);
    }

    function proxyRenewRent(address renter, string memory machineId, uint256 additionalRentSeconds) external {
        _renewRent(renter, machineId, additionalRentSeconds);
    }

    function renewRent(string memory machineId, uint256 additionalRentSeconds) external {
        _renewRent(msg.sender, machineId, additionalRentSeconds);
    }

    function proxyRenewRentV2(address renter, string memory machineId, uint256 additionalRentSeconds) external {
        _renewRentV2(renter, machineId, additionalRentSeconds);
    }

    function renewRentV2(string memory machineId, uint256 additionalRentSeconds) external {
        _renewRentV2(msg.sender, machineId, additionalRentSeconds);
    }

    function _renewRent(address renter, string memory machineId, uint256 additionalRentSeconds) internal {
        uint256 rentId = machineId2RentId[machineId];
        require(rentId2RentInfo[rentId].rentEndTime > block.timestamp, RentEnd());
        require(rentId2RentInfo[rentId].renter == renter, NotRenter());
        require(isRented(machineId), MachineNotRented());
        require(rentId2FeeInfoInDLC[rentId].isV1, "V1 renew on V2 rental forbidden");
        require(
            additionalRentSeconds >= 10 minutes && additionalRentSeconds <= 10 hours,
            InvalidRentDuration(additionalRentSeconds)
        );

        (,,, uint256 endAtTimestamp,,,,) = stakingContract.getMachineInfo(machineId);
        (,, uint256 rewardEndAt) = stakingContract.getGlobalState();
        uint256 minEndTime = Math.min(endAtTimestamp, rewardEndAt);
        require(minEndTime > block.timestamp, "machine or reward period expired");
        uint256 maxRentDuration =
                            Math.min(minEndTime - block.timestamp, stakingContract.getRewardDuration());

        require(
            rentId2RentInfo[rentId].rentEndTime + additionalRentSeconds < endAtTimestamp,
            RenTimeCannotOverMachineUnstakeTime()
        );

        if (msg.sender != renter) {
            require(machine2ProxyRented[machineId] == true, NotProxyRentingMachine());
        }

        uint256 newRentDuration = rentId2RentInfo[rentId].rentEndTime - block.timestamp + additionalRentSeconds;
        require(newRentDuration <= maxRentDuration, RentDurationTooLong(newRentDuration, maxRentDuration));

        (,, uint256 platformFeeRate) = stakingContract.getMachineConfig(machineId);

        uint256 baseRentFee = getBaseMachinePrice(machineId, additionalRentSeconds);
        uint256 extraRentFee = getExtraRentFee(machineId, additionalRentSeconds);
        uint256 platformFee = (baseRentFee + extraRentFee) * platformFeeRate / 100;
        uint256 additionalRentFeeInFact = baseRentFee + extraRentFee + platformFee;
        require(feeToken.balanceOf(msg.sender) >= additionalRentFeeInFact, BalanceNotEnough());

        // Update rent end time
        rentId2RentInfo[rentId].rentEndTime += additionalRentSeconds;

        FeeInfo storage feeInfo = rentId2FeeInfoInDLC[rentId];
        feeInfo.baseFee += baseRentFee;
        feeInfo.extraFee += extraRentFee;
        feeInfo.platformFee += platformFee;

        SafeERC20.safeTransferFrom(feeToken, msg.sender, address(this), platformFee + extraRentFee + baseRentFee);

        (address machineHolder,) = getMachineHolderAndCalcPoint(machineId);

        // update total burned amount
        stakingContract.renewRentMachine(machineId, additionalRentFeeInFact);
        emit RenewRent(machineHolder, machineId, rentId, additionalRentSeconds, additionalRentFeeInFact, renter);
    }

    function _renewRentV2(address renter, string memory machineId, uint256 additionalRentSeconds) internal {
        uint256 rentId = machineId2RentId[machineId];
        require(rentId2RentInfo[rentId].rentEndTime > block.timestamp, RentEnd());
        require(rentId2RentInfo[rentId].renter == renter, NotRenter());
        require(isRented(machineId), MachineNotRented());
        require(!rentId2FeeInfoInDLC[rentId].isV1, "V2 renew on V1 rental forbidden");
        require(
            additionalRentSeconds >= 10 minutes && additionalRentSeconds <= 10 hours,
            InvalidRentDuration(additionalRentSeconds)
        );

        (,,, uint256 endAtTimestamp,,,,) = stakingContract.getMachineInfo(machineId);
        (,, uint256 rewardEndAt) = stakingContract.getGlobalState();
        uint256 minEndTime = Math.min(endAtTimestamp, rewardEndAt);
        require(minEndTime > block.timestamp, "machine or reward period expired");
        uint256 maxRentDuration =
            Math.min(minEndTime - block.timestamp, stakingContract.getRewardDuration());

        require(
            rentId2RentInfo[rentId].rentEndTime + additionalRentSeconds < endAtTimestamp,
            RenTimeCannotOverMachineUnstakeTime()
        );

        if (msg.sender != renter) {
            require(machine2ProxyRented[machineId] == true, NotProxyRentingMachine());
        }

        uint256 newRentDuration = rentId2RentInfo[rentId].rentEndTime - block.timestamp + additionalRentSeconds;
        require(newRentDuration <= maxRentDuration, RentDurationTooLong(newRentDuration, maxRentDuration));

        (,, uint256 platformFeeRate) = stakingContract.getMachineConfig(machineId);

        uint256 baseRentFee = getBaseMachinePrice(machineId, additionalRentSeconds);
        uint256 extraRentFee = getExtraRentFee(machineId, additionalRentSeconds);
        uint256 platformFee = (baseRentFee + extraRentFee) * platformFeeRate / 100;
        uint256 extraRentFeeInPoint = getExtraRentFeeInPoint(machineId, additionalRentSeconds);

        uint256 additionalRentFeeInFact = baseRentFee + platformFee;
        require(feeToken.balanceOf(msg.sender) >= additionalRentFeeInFact, BalanceNotEnough());

        // Update rent end time
        rentId2RentInfo[rentId].rentEndTime += additionalRentSeconds;

        FeeInfo storage feeInfo = rentId2FeeInfoInDLC[rentId];
        feeInfo.baseFee += baseRentFee;
        feeInfo.extraFee += extraRentFeeInPoint;
        feeInfo.platformFee += platformFee;

        SafeERC20.safeTransferFrom(feeToken, msg.sender, address(this), platformFee + baseRentFee);
        IERC20 pointToken = IERC20(address(0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6));
        SafeERC20.safeTransferFrom(pointToken, msg.sender, address(this), extraRentFeeInPoint);
        (address machineHolder,) = getMachineHolderAndCalcPoint(machineId);

        // update total burned amount
        stakingContract.renewRentMachine(machineId, additionalRentFeeInFact);
        emit RenewRent(machineHolder, machineId, rentId, additionalRentSeconds, additionalRentFeeInFact, renter);
    }

    function endRentMachineV2(string calldata machineId) external nonReentrant {
        uint256 rentId = machineId2RentId[machineId];
        RentInfo memory rentInfo = rentId2RentInfo[rentId];
        bool isProxyRenting = machine2ProxyRented[machineId];
        address payer = machine2ProxyRentPayer[machineId];
        if (msg.sender != rentInfo.renter && msg.sender != payer) {
            require(rentInfo.rentEndTime <= block.timestamp, RentNotEnd());
        } else {
            if (isProxyRenting){
                require(payer != address(0), "proxy rent payer is zero address");
            }else{
                payer = msg.sender;
            }
        }
        machine2ProxyRented[machineId] = false;
        require(rentInfo.rentEndTime > 0, RentingNotExist());

        (address machineHolder,) = getMachineHolderAndCalcPoint(machineId);

        FeeInfo memory feeInfo = rentId2FeeInfoInDLC[rentId];

        IERC20 pointToken = IERC20(address(0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6));
        uint256 pointTokenBalance = pointToken.balanceOf(address(this));

        // 计算实际可用的 Point Token（取记录值和实际余额的较小值）
        uint256 availablePointToken = feeInfo.extraFee > pointTokenBalance ? pointTokenBalance : feeInfo.extraFee;

        uint256 _now = block.timestamp;
        uint256 paybackExtraFee = 0;
        if (_now < rentInfo.rentEndTime) {
            uint256 rentDuration = rentInfo.rentEndTime - rentInfo.rentStatTime;
            uint256 usedDuration = _now - rentInfo.rentStatTime;

            uint256 totalRentDLCFee = feeInfo.baseFee + feeInfo.platformFee;

            // 使用乘法优先避免精度损失: (value * usedDuration) / rentDuration
            uint256 usedBaseFee = (feeInfo.baseFee * usedDuration) / rentDuration;
            uint256 usedExtraRentFee = (availablePointToken * usedDuration) / rentDuration;
            uint256 usedPlatformFee = (feeInfo.platformFee * usedDuration) / rentDuration;

            paybackExtraFee = availablePointToken - usedExtraRentFee;
            uint256 payBackDLCFee = totalRentDLCFee - usedBaseFee - usedPlatformFee;

            feeInfo.baseFee = usedBaseFee;
            feeInfo.extraFee = usedExtraRentFee;
            feeInfo.platformFee = usedPlatformFee;

            if (payBackDLCFee > 0) {
                SafeERC20.safeTransfer(feeToken, payer, payBackDLCFee);
                emit PayBackFee(machineId, rentId, payer, payBackDLCFee);
            }
            if (paybackExtraFee > 0) {
                SafeERC20.safeTransfer(pointToken, payer, paybackExtraFee);
                emit PayBackPointFee(machineId, rentId, payer, paybackExtraFee);
            }

            emit RentTime(rentDuration, usedDuration);
        } else {
            // 租期已结束，全部可用的 extraFee 给 machineHolder
            feeInfo.extraFee = availablePointToken;
        }

        if (feeInfo.baseFee > 0) {
            feeToken.approve(address(this), feeInfo.baseFee);
            feeToken.burnFrom(address(this), feeInfo.baseFee);
            emit BurnedFee(machineId, lastRentId, block.timestamp, feeInfo.baseFee, rentInfo.renter, 1);
            totalBurnedAmount += feeInfo.baseFee;
        }

        if (feeInfo.extraFee > 0) {
            SafeERC20.safeTransfer(pointToken, machineHolder, feeInfo.extraFee);
            emit ExtraRentFeeTransfer(machineHolder, lastRentId, feeInfo.extraFee);
        }
        if (feeInfo.platformFee > 0) {
            distributePlatformFee(rentId, machineId, feeInfo.platformFee);
        }

        stakingContract.endRentMachine(machineId, feeInfo.baseFee, feeInfo.extraFee);
        machineId2LastRentEndBlock[machineId] = block.number;

        // 状态删除放在最后
        delete rentId2RentInfo[rentId];
        delete machineId2RentId[machineId];
        delete machineId2IsMonthlyRent[machineId];
        delete rentId2FeeInfoInDLC[rentId];
        emit EndRentMachine(machineHolder, rentId, machineId, rentInfo.rentEndTime, rentInfo.renter);
    }

    function endRentMachine(string calldata machineId) external nonReentrant {
        uint256 rentId = machineId2RentId[machineId];
        RentInfo memory rentInfo = rentId2RentInfo[rentId];
        bool isProxyRenting = machine2ProxyRented[machineId];
        address payer = machine2ProxyRentPayer[machineId];
        if (msg.sender != rentInfo.renter && msg.sender != payer) {
            require(rentInfo.rentEndTime <= block.timestamp, RentNotEnd());
        } else {
            if (isProxyRenting){
                require(payer != address(0), "proxy rent payer is zero address");
            }else{
                payer = msg.sender;
            }
        }
        machine2ProxyRented[machineId] = false;
        require(rentInfo.rentEndTime > 0, RentingNotExist());

        (address machineHolder,) = getMachineHolderAndCalcPoint(machineId);

        FeeInfo memory feeInfo = rentId2FeeInfoInDLC[rentId];

        uint256 _now = block.timestamp;

        // V1 租用: extraFee 是 DLC; V2 租用: extraFee 是 Point Token
        if (!feeInfo.isV1) {
            // V2 (或旧数据默认): extraFee 是 Point Token
            IERC20 pointToken = IERC20(address(0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6));
            uint256 pointTokenBalance = pointToken.balanceOf(address(this));
            uint256 availablePointToken = feeInfo.extraFee > pointTokenBalance ? pointTokenBalance : feeInfo.extraFee;

            if (_now < rentInfo.rentEndTime) {
                uint256 rentDuration = rentInfo.rentEndTime - rentInfo.rentStatTime;
                uint256 usedDuration = _now - rentInfo.rentStatTime;

                uint256 usedBaseFee = (feeInfo.baseFee * usedDuration) / rentDuration;
                uint256 usedExtraRentFee = (availablePointToken * usedDuration) / rentDuration;
                uint256 usedPlatformFee = (feeInfo.platformFee * usedDuration) / rentDuration;

                uint256 paybackExtraFee = availablePointToken - usedExtraRentFee;
                uint256 payBackDLCFee = (feeInfo.baseFee - usedBaseFee) + (feeInfo.platformFee - usedPlatformFee);

                feeInfo.baseFee = usedBaseFee;
                feeInfo.extraFee = usedExtraRentFee;
                feeInfo.platformFee = usedPlatformFee;

                if (payBackDLCFee > 0) {
                    SafeERC20.safeTransfer(feeToken, payer, payBackDLCFee);
                    emit PayBackFee(machineId, rentId, payer, payBackDLCFee);
                }
                if (paybackExtraFee > 0) {
                    SafeERC20.safeTransfer(pointToken, payer, paybackExtraFee);
                    emit PayBackPointFee(machineId, rentId, payer, paybackExtraFee);
                }

                emit RentTime(rentDuration, usedDuration);
            } else {
                feeInfo.extraFee = availablePointToken;
            }

            // 销毁 baseFee
            if (feeInfo.baseFee > 0) {
                feeToken.approve(address(this), feeInfo.baseFee);
                feeToken.burnFrom(address(this), feeInfo.baseFee);
                emit BurnedFee(machineId, rentId, block.timestamp, feeInfo.baseFee, rentInfo.renter, 1);
                totalBurnedAmount += feeInfo.baseFee;
            }

            // extraFee (Point Token) 转给机器持有者
            if (feeInfo.extraFee > 0) {
                SafeERC20.safeTransfer(pointToken, machineHolder, feeInfo.extraFee);
                emit ExtraRentFeeTransfer(machineHolder, rentId, feeInfo.extraFee);
            }
        } else {
            // V1 (isV1 = true): extraFee 是 DLC
            if (_now < rentInfo.rentEndTime) {
                uint256 rentDuration = rentInfo.rentEndTime - rentInfo.rentStatTime;
                uint256 usedDuration = _now - rentInfo.rentStatTime;

                uint256 usedBaseFee = (feeInfo.baseFee * usedDuration) / rentDuration;
                uint256 usedExtraRentFee = (feeInfo.extraFee * usedDuration) / rentDuration;
                uint256 usedPlatformFee = (feeInfo.platformFee * usedDuration) / rentDuration;

                uint256 paybackExtraFee = feeInfo.extraFee - usedExtraRentFee;
                uint256 payBackDLCFee = (feeInfo.baseFee - usedBaseFee) + (feeInfo.platformFee - usedPlatformFee) + paybackExtraFee;

                feeInfo.baseFee = usedBaseFee;
                feeInfo.extraFee = usedExtraRentFee;
                feeInfo.platformFee = usedPlatformFee;

                if (payBackDLCFee > 0) {
                    SafeERC20.safeTransfer(feeToken, payer, payBackDLCFee);
                    emit PayBackFee(machineId, rentId, payer, payBackDLCFee);
                }

                emit RentTime(rentDuration, usedDuration);
            }

            // 销毁 baseFee
            if (feeInfo.baseFee > 0) {
                feeToken.approve(address(this), feeInfo.baseFee);
                feeToken.burnFrom(address(this), feeInfo.baseFee);
                emit BurnedFee(machineId, rentId, block.timestamp, feeInfo.baseFee, rentInfo.renter, 1);
                totalBurnedAmount += feeInfo.baseFee;
            }

            // extraFee (DLC) 转给机器持有者
            if (feeInfo.extraFee > 0) {
                SafeERC20.safeTransfer(feeToken, machineHolder, feeInfo.extraFee);
                emit ExtraRentFeeTransfer(machineHolder, rentId, feeInfo.extraFee);
            }
        }

        // platformFee 分配
        if (feeInfo.platformFee > 0) {
            distributePlatformFee(rentId, machineId, feeInfo.platformFee);
        }

        stakingContract.endRentMachine(machineId, feeInfo.baseFee, feeInfo.extraFee);
        machineId2LastRentEndBlock[machineId] = block.number;

        // 状态删除放在最后
        delete rentId2RentInfo[rentId];
        delete machineId2RentId[machineId];
        delete machineId2IsMonthlyRent[machineId];
        delete rentId2FeeInfoInDLC[rentId];
        emit EndRentMachine(machineHolder, rentId, machineId, rentInfo.rentEndTime, rentInfo.renter);
    }

    function getMachineHolderAndCalcPoint(string memory machineId) public view returns (address, uint256) {
        (address holder, uint256 calcPoint,,,,,,) = stakingContract.getMachineInfo(machineId);
        return (holder, calcPoint);
    }

    function reportMachineFault(string calldata machineId, uint256 reserveAmount) external {
        require(reserveAmount == REPORT_RESERVE_AMOUNT, ReserveAmountForReportShouldBe10000());

        uint256 rentId = machineId2RentId[machineId];
        RentInfo memory rentInfo = rentId2RentInfo[rentId];
        require(rentInfo.renter == msg.sender, NotRenter());
        require(rentInfo.rentEndTime >= block.timestamp, RentEnd());

        SafeERC20.safeTransferFrom(feeToken, msg.sender, address(this), REPORT_RESERVE_AMOUNT);
        machineId2SlashInfo[rentInfo.machineId] = newSlashInfo(
            rentInfo.stakeHolder,
            rentInfo.machineId,
            SLASH_AMOUNT,
            rentInfo.rentStatTime,
            rentInfo.rentEndTime,
            block.timestamp - rentInfo.rentStatTime,
            SlashType.RenterReport,
            rentInfo.renter
        );
        pendingSlashMachineIds.push(rentInfo.machineId);
        emit ReportMachineFault(rentId, rentInfo.machineId, msg.sender);
    }

    function newSlashInfo(
        address slasher,
        string memory machineId,
        uint256 slashAmount,
        uint256 rentStartAt,
        uint256 rentEndAt,
        uint256 rentDuration,
        SlashType slashType,
        address renter
    ) internal view returns (SlashInfo memory) {
        SlashInfo memory slashInfo = SlashInfo({
            stakeHolder: slasher,
            machineId: machineId,
            slashAmount: slashAmount,
            rentStartAtTimestamp: rentStartAt,
            rentEndAtTimestamp: rentEndAt,
            rentedDurationSeconds: rentDuration,
            renter: renter,
            slashType: slashType,
            createdAt: block.timestamp,
            paid: false
        });
        return slashInfo;
    }

    function addSlashInfoAndReport(SlashInfo memory slashInfo) internal {
        machineId2SlashInfos[slashInfo.machineId].push(slashInfo);
        machineId2UnpaidSlashCount[slashInfo.machineId]++;
        machineId2LastSlashTimestamp[slashInfo.machineId] = block.timestamp;
        stakingContract.reportMachineFault(slashInfo.machineId, slashInfo.renter);
    }

    /// @notice 轻量惩罚版本：记录 slash 信息，但调用 NFTStaking 的轻量惩罚（不解质押）
    function addSlashInfoAndReportLight(SlashInfo memory slashInfo) internal {
        machineId2SlashInfos[slashInfo.machineId].push(slashInfo);
        machineId2UnpaidSlashCount[slashInfo.machineId]++;
        machineId2LastSlashTimestamp[slashInfo.machineId] = block.timestamp;
        stakingContract.reportMachineFaultLight(slashInfo.machineId, slashInfo.renter);
    }

    function approveMachineFaultReporting(string calldata machineId) external onlyApproveAdmins {
        require(machineId2SlashInfo[machineId].renter != address(0x0), ReportedMachineNotFound());

        require(pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] != Vote.Finished, VoteFinished());
        pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] = Vote.Yes;
        emit ApprovedReport(machineId, msg.sender);
        pendingSlashMachineId2ApprovedCount[machineId] += 1;
        if (pendingSlashMachineId2ApprovedCount[machineId] >= voteThreshold) {
            SlashInfo memory slashInfo = machineId2SlashInfo[machineId];
            addSlashInfoAndReport(slashInfo);

            removeValueOfStringArray(machineId, pendingSlashMachineIds);
            delete machineId2SlashInfo[machineId];
            delete pendingSlashMachineId2ApprovedCount[machineId];

            for (uint8 i = 0; i < adminsToApprove.length; i++) {
                pendingSlashMachineId2ApprovedAdmins[machineId][adminsToApprove[i]] = Vote.Finished;
            }

            SafeERC20.safeTransfer(feeToken, slashInfo.renter, REPORT_RESERVE_AMOUNT);
            emit ExecuteReport(machineId, Vote.Yes);
        }
    }

    function rejectMachineFaultReporting(string calldata machineId) external onlyApproveAdmins {
        require(machineId2SlashInfo[machineId].renter != address(0), ReportedMachineNotFound());

        require(pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] != Vote.Finished, VoteFinished());
        pendingSlashMachineId2ApprovedAdmins[machineId][msg.sender] = Vote.No;
        pendingSlashMachineId2RefuseCount[machineId] += 1;
        emit RefusedReport(machineId, msg.sender);
        if (pendingSlashMachineId2RefuseCount[machineId] >= voteThreshold) {
            removeValueOfStringArray(machineId, pendingSlashMachineIds);
            delete machineId2SlashInfo[machineId];
            delete pendingSlashMachineId2ApprovedCount[machineId];

            for (uint8 i = 0; i < adminsToApprove.length; i++) {
                pendingSlashMachineId2ApprovedAdmins[machineId][adminsToApprove[i]] = Vote.Finished;
            }

            uint256 amountPerAdmin = REPORT_RESERVE_AMOUNT / adminsToApprove.length;
            for (uint256 i = 0; i < adminsToApprove.length; i++) {
                if (adminsToApprove[i] == address(0)) {
                    continue;
                }
                SafeERC20.safeTransfer(feeToken, adminsToApprove[i], amountPerAdmin);
            }

            delete machineId2SlashInfo[machineId];
            delete pendingSlashMachineId2RefuseCount[machineId];

            emit ExecuteReport(machineId, Vote.No);
        }
    }

    function version() external pure returns (uint256) {
        return 10;
    }

    /// @notice H-2: 初始化白名单计数器（升级后一次性调用，同步已有白名单数量）
    function initializeWhitelistCount(uint256 count) external onlyOwner {
        require(rentWhitelistCount == 0, "already initialized");
        rentWhitelistCount = count;
    }

    /// @notice v6 升级初始化：同步已有未赔付 slash 的计数器
    /// @param machineIds 已知有未赔付 slash 的 machineId 列表（由链下脚本扫描得出）
    function initializeV6(string[] calldata machineIds) external reinitializer(6) {
        for (uint256 i = 0; i < machineIds.length; i++) {
            SlashInfo[] storage infos = machineId2SlashInfos[machineIds[i]];
            uint256 count = 0;
            for (uint256 j = 0; j < infos.length; j++) {
                if (!infos[j].paid) {
                    count++;
                }
            }
            machineId2UnpaidSlashCount[machineIds[i]] = count;
        }
    }

    function hasUnpaidSlash(string memory machineId) external view returns (bool) {
        return machineId2UnpaidSlashCount[machineId] > 0;
    }

    function payPendingSlash(string calldata machineId) external nonReentrant {
        require(machineId2UnpaidSlashCount[machineId] > 0, NoUnpaidSlash());
        SlashInfo[] storage infos = machineId2SlashInfos[machineId];
        for (uint256 i = 0; i < infos.length; i++) {
            if (!infos[i].paid) {
                SafeERC20.safeTransferFrom(IERC20(address(feeToken)), msg.sender, infos[i].renter, infos[i].slashAmount);
                infos[i].paid = true;
                machineId2UnpaidSlashCount[machineId]--;
                emit SlashPaidByStakeHolder(machineId, msg.sender, infos[i].renter, infos[i].slashAmount);
                emit PaidSlash(machineId);
            }
        }
        // 全部赔付后清零，表示机器恢复正常状态
        if (machineId2UnpaidSlashCount[machineId] == 0) {
            machineId2LastSlashTimestamp[machineId] = 0;
        }
    }

    function getTotalBurnedRentFee() public view returns (uint256) {
        return totalBurnedAmount;
    }

    function getRentedGPUCountOfStakeHolder(address stakeHolder) public view returns (uint256) {
        return stakeHolder2RentGPUInfo[stakeHolder].rentedGPUCount;
    }

    function getTotalRentedGPUCount() public view returns (uint256) {
        return rentGPUInfo.rentedGPUCount;
    }

    function isRented(string memory machineId) public view returns (bool) {
        uint256 rentId = machineId2RentId[machineId];
        RentInfo memory rentInfo = rentId2RentInfo[rentId];
        if (rentInfo.renter != address(0)) {
            return true;
        }
        uint256 lastRentEndBlock = machineId2LastRentEndBlock[machineId];
        if (lastRentEndBlock > 0) {
            return block.number <= lastRentEndBlock + 30;
        }
        return false;
    }

    function getRenter(string calldata machineId) public view returns (address) {
        uint256 rentId = machineId2RentId[machineId];
        address renter = rentId2RentInfo[rentId].renter;
        return renter;
    }

    function notify(NotifyType tp, string calldata machineId) external nonReentrant onlyDBCAIContract returns (bool) {
        if (tp == NotifyType.ContractRegister) {
            registered = true;
            return true;
        }

        bool isStaking = stakingContract.isStaking(machineId);
        if (!isStaking) {
            return false;
        }

        if (tp == NotifyType.MachineOffline) {
            uint256 rentId = machineId2RentId[machineId];
            RentInfo memory rentInfo = rentId2RentInfo[rentId];
            if (
                rentInfo.renter != address(0) && block.timestamp <= rentInfo.rentEndTime
                    && block.timestamp > rentInfo.rentStatTime
            ) {
                // 包月租赁离线：不惩罚、不终止，仅停止挖矿奖励
                if (machineId2IsMonthlyRent[machineId]) {
                    stakingContract.stopRewarding(machineId);
                    emit RemoveCalcPointOnOffline(machineId);
                    return true;
                }
                // 非包月：触发轻量 slash 流程（扣罚金+结束租赁，不解质押不下架）+ 按比例退费 + 清理状态
                SlashInfo memory slashInfo = newSlashInfo(
                    rentInfo.stakeHolder,
                    rentInfo.machineId,
                    SLASH_AMOUNT,
                    rentInfo.rentStatTime,
                    rentInfo.rentEndTime,
                    block.timestamp - rentInfo.rentStatTime,
                    SlashType.Offline,
                    rentInfo.renter
                );
                addSlashInfoAndReportLight(slashInfo);

                // 惩罚性退费：未用部分全退 + 已用部分最多24h也退给租户（矿工不拿）
                _terminateRentOnSlashWithPenalty(machineId, rentId, rentInfo);

                emit SlashMachineOnOffline(
                    rentInfo.stakeHolder,
                    rentInfo.machineId,
                    rentInfo.renter,
                    1000 ether,
                    rentInfo.rentStatTime,
                    rentInfo.rentEndTime,
                    SlashType.Offline
                );
            } else if (rentInfo.renter != address(0) && block.timestamp > rentInfo.rentEndTime) {
                // 租赁已过期但未清理，强制清理租赁状态并处理费用
                _cleanupExpiredRentOnOffline(machineId, rentId, rentInfo);
            } else {
                stakingContract.stopRewarding(machineId);
                emit RemoveCalcPointOnOffline(machineId);
            }
        } else if (tp == NotifyType.MachineOnline && stakingContract.isStakingButOffline(machineId)) {
            stakingContract.recoverRewarding(machineId);
            emit AddCalcPointOnline(machineId);
        }else if (tp == NotifyType.MachineUnregister) {
            stakingContract.updateMachineRegisterStatus(machineId,false);
        }else if (tp == NotifyType.MachineRegister) {
            stakingContract.updateMachineRegisterStatus(machineId,true);
        }
        return true;
    }
    function getSlashInfosByMachineId(string memory machineId, uint256 pageNumber, uint256 pageSize)
        external
        view
        returns (SlashInfo[] memory paginatedSlashInfos, uint256 totalCount)
    {
        totalCount = machineId2SlashInfos[machineId].length;

        if (pageNumber == 0 || pageSize == 0 || totalCount == 0) {
            return (new SlashInfo[](0), 0);
        }

        // Calculate the start index for the requested page
        uint256 startIndex = (pageNumber - 1) * pageSize;

        // Ensure startIndex is within bounds
        if (startIndex >= totalCount) {
            return (new SlashInfo[](0), totalCount);
        }

        // Calculate the end index for pagination
        uint256 endIndex = startIndex + pageSize > totalCount ? totalCount : startIndex + pageSize;
        uint256 resultSize = endIndex - startIndex;

        // Create a new array for paginated results
        paginatedSlashInfos = new SlashInfo[](resultSize);

        // Populate the paginated array
        for (uint256 i = 0; i < resultSize; i++) {
            paginatedSlashInfos[i] = machineId2SlashInfos[machineId][startIndex + i];
        }
    }

    function paidSlash(string memory machineId) external onlyStakingContract {
        SlashInfo[] storage slashInfos = machineId2SlashInfos[machineId];
        for (uint256 i = 0; i < slashInfos.length; i++) {
            if (slashInfos[i].paid) {
                continue;
            }
            slashInfos[i].paid = true;
            if (machineId2UnpaidSlashCount[machineId] > 0) {
                machineId2UnpaidSlashCount[machineId]--;
            }
            // 全部赔付后清零，表示机器恢复正常状态
            if (machineId2UnpaidSlashCount[machineId] == 0) {
                machineId2LastSlashTimestamp[machineId] = 0;
            }
            emit PaidSlash(machineId);
            return;
        }
    }

    function isInSlashing(string memory machineId) public view returns (bool) {
        return machineId2SlashInfo[machineId].renter != address(0) && machineId2SlashInfo[machineId].paid == false;
    }

    /// @notice 租赁进行中机器离线时，终止租赁并按比例退费给用户
    /// @dev Slash 流程调用此函数，按已用时间计算费用，剩余退还给租户
    function _terminateRentOnSlash(string memory machineId, uint256 rentId, RentInfo memory rentInfo) internal {
        FeeInfo memory feeInfo = rentId2FeeInfoInDLC[rentId];

        // 计算已用时间比例
        uint256 rentDuration = rentInfo.rentEndTime - rentInfo.rentStatTime;
        uint256 usedDuration = block.timestamp - rentInfo.rentStatTime;

        // 防止除零
        if (rentDuration == 0) {
            rentDuration = 1;
        }

        // 计算各费用的已用部分
        uint256 usedBaseFee = (feeInfo.baseFee * usedDuration) / rentDuration;
        uint256 usedPlatformFee = (feeInfo.platformFee * usedDuration) / rentDuration;

        // 获取付款人（代理租用或租户自己）
        address payer = machine2ProxyRented[machineId] ? machine2ProxyRentPayer[machineId] : rentInfo.renter;
        if (payer == address(0)) {
            payer = rentInfo.renter;
        }

        if (!feeInfo.isV1) {
            // V2 (或旧数据默认): extraFee 是 Point Token
            IERC20 pointToken = IERC20(address(0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6));
            uint256 pointTokenBalance = pointToken.balanceOf(address(this));
            uint256 availablePointToken = feeInfo.extraFee > pointTokenBalance ? pointTokenBalance : feeInfo.extraFee;
            uint256 usedExtraFee = (availablePointToken * usedDuration) / rentDuration;

            // 计算退还金额
            uint256 payBackDLCFee = (feeInfo.baseFee - usedBaseFee) + (feeInfo.platformFee - usedPlatformFee);
            uint256 payBackExtraFee = availablePointToken - usedExtraFee;

            // 退还 DLC 给付款人
            if (payBackDLCFee > 0) {
                SafeERC20.safeTransfer(feeToken, payer, payBackDLCFee);
                emit PayBackFee(machineId, rentId, payer, payBackDLCFee);
            }

            // 退还 Point Token 给付款人
            if (payBackExtraFee > 0) {
                SafeERC20.safeTransfer(pointToken, payer, payBackExtraFee);
                emit PayBackExtraFee(machineId, rentId, payer, payBackExtraFee);
            }

            // 销毁已用的 baseFee
            if (usedBaseFee > 0) {
                feeToken.approve(address(this), usedBaseFee);
                feeToken.burnFrom(address(this), usedBaseFee);
                emit BurnedFee(machineId, rentId, block.timestamp, usedBaseFee, rentInfo.renter, 1);
                totalBurnedAmount += usedBaseFee;
            }

            // 已用的 extraFee (Point Token) 转给机器持有者
            if (usedExtraFee > 0) {
                SafeERC20.safeTransfer(pointToken, rentInfo.stakeHolder, usedExtraFee);
                emit ExtraRentFeeTransfer(rentInfo.stakeHolder, rentId, usedExtraFee);
            }
        } else {
            // V1 (isV1 = true): extraFee 是 DLC
            uint256 usedExtraFee = (feeInfo.extraFee * usedDuration) / rentDuration;
            uint256 payBackExtraFee = feeInfo.extraFee - usedExtraFee;

            // 计算退还金额 (DLC)
            uint256 payBackDLCFee = (feeInfo.baseFee - usedBaseFee) + (feeInfo.platformFee - usedPlatformFee) + payBackExtraFee;

            // 退还 DLC 给付款人
            if (payBackDLCFee > 0) {
                SafeERC20.safeTransfer(feeToken, payer, payBackDLCFee);
                emit PayBackFee(machineId, rentId, payer, payBackDLCFee);
            }

            // 销毁已用的 baseFee
            if (usedBaseFee > 0) {
                feeToken.approve(address(this), usedBaseFee);
                feeToken.burnFrom(address(this), usedBaseFee);
                emit BurnedFee(machineId, rentId, block.timestamp, usedBaseFee, rentInfo.renter, 1);
                totalBurnedAmount += usedBaseFee;
            }

            // 已用的 extraFee (DLC) 转给机器持有者
            if (usedExtraFee > 0) {
                SafeERC20.safeTransfer(feeToken, rentInfo.stakeHolder, usedExtraFee);
                emit ExtraRentFeeTransfer(rentInfo.stakeHolder, rentId, usedExtraFee);
            }
        }

        // 已用的 platformFee 分配给平台
        if (usedPlatformFee > 0) {
            distributePlatformFee(rentId, machineId, usedPlatformFee);
        }

        // 清理 Rent 合约状态
        machineId2LastRentEndBlock[machineId] = block.number;
        machine2ProxyRented[machineId] = false;
        delete rentId2RentInfo[rentId];
        delete machineId2RentId[machineId];
        delete machineId2IsMonthlyRent[machineId];
        delete rentId2FeeInfoInDLC[rentId];

        emit EndRentMachine(rentInfo.stakeHolder, rentId, machineId, block.timestamp, rentInfo.renter);
    }

    /// @notice 惩罚性退费：未用部分全退 + 已用部分最多24h也退给租户（矿工不拿）
    /// @dev 与 _terminateRentOnSlash 区别：矿工已赚的 extraFee（最多24h）作为惩罚退给租户
    function _terminateRentOnSlashWithPenalty(string memory machineId, uint256 rentId, RentInfo memory rentInfo) internal {
        FeeInfo memory feeInfo = rentId2FeeInfoInDLC[rentId];

        uint256 rentDuration = rentInfo.rentEndTime - rentInfo.rentStatTime;
        uint256 usedDuration = block.timestamp - rentInfo.rentStatTime;
        if (rentDuration == 0) { rentDuration = 1; }

        // 惩罚上限：已使用部分最多 24 小时
        uint256 penaltyDuration = usedDuration > 24 hours ? 24 hours : usedDuration;

        uint256 usedBaseFee = (feeInfo.baseFee * usedDuration) / rentDuration;
        uint256 usedPlatformFee = (feeInfo.platformFee * usedDuration) / rentDuration;

        address payer = machine2ProxyRented[machineId] ? machine2ProxyRentPayer[machineId] : rentInfo.renter;
        if (payer == address(0)) { payer = rentInfo.renter; }

        if (!feeInfo.isV1) {
            // V2: extraFee 是 Point Token (DLP)
            IERC20 pointToken = IERC20(address(0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6));
            uint256 pointTokenBalance = pointToken.balanceOf(address(this));
            uint256 availablePointToken = feeInfo.extraFee > pointTokenBalance ? pointTokenBalance : feeInfo.extraFee;
            uint256 usedExtraFee = (availablePointToken * usedDuration) / rentDuration;

            // 惩罚部分：已用 extraFee 中最多 24h 的金额退给租户（不给矿工）
            uint256 penaltyExtraFee = (availablePointToken * penaltyDuration) / rentDuration;
            // 超出 24h 惩罚的部分正常给矿工
            uint256 minerExtraFee = usedExtraFee > penaltyExtraFee ? usedExtraFee - penaltyExtraFee : 0;

            // 退给租户：未使用部分 + 惩罚部分
            uint256 payBackExtraFee = (availablePointToken - usedExtraFee) + penaltyExtraFee;
            uint256 payBackDLCFee = (feeInfo.baseFee - usedBaseFee) + (feeInfo.platformFee - usedPlatformFee);

            if (payBackDLCFee > 0) {
                SafeERC20.safeTransfer(feeToken, payer, payBackDLCFee);
                emit PayBackFee(machineId, rentId, payer, payBackDLCFee);
            }
            if (payBackExtraFee > 0) {
                uint256 ptBal0 = pointToken.balanceOf(address(this));
                uint256 refundPt = payBackExtraFee > ptBal0 ? ptBal0 : payBackExtraFee;
                if (refundPt > 0) {
                    SafeERC20.safeTransfer(pointToken, payer, refundPt);
                    emit PayBackExtraFee(machineId, rentId, payer, refundPt);
                }
                // M-2: 记录余额不足导致的退款差额，供链下系统补偿
                if (refundPt < payBackExtraFee) {
                    emit PayBackExtraFeeShortfall(machineId, rentId, payer, payBackExtraFee, refundPt);
                }
            }

            // burn 和转账前检查余额，防止 revert 阻塞 notify
            {
                uint256 dlcBal = feeToken.balanceOf(address(this));
                uint256 burnAmt = usedBaseFee > dlcBal ? dlcBal : usedBaseFee;
                if (burnAmt > 0) {
                    feeToken.approve(address(this), burnAmt);
                    feeToken.burnFrom(address(this), burnAmt);
                    emit BurnedFee(machineId, rentId, block.timestamp, burnAmt, rentInfo.renter, 1);
                    totalBurnedAmount += burnAmt;
                }
            }

            // 矿工只拿超过 24h 惩罚的部分
            if (minerExtraFee > 0) {
                uint256 ptBal = pointToken.balanceOf(address(this));
                uint256 transferAmt = minerExtraFee > ptBal ? ptBal : minerExtraFee;
                if (transferAmt > 0) {
                    SafeERC20.safeTransfer(pointToken, rentInfo.stakeHolder, transferAmt);
                    emit ExtraRentFeeTransfer(rentInfo.stakeHolder, rentId, transferAmt);
                }
            }
        } else {
            // V1: extraFee 是 DLC — 加余额保护防止 revert 导致整个 notify 阻塞
            uint256 dlcBalance = feeToken.balanceOf(address(this));
            uint256 availableDLC = feeInfo.extraFee > dlcBalance ? dlcBalance : feeInfo.extraFee;
            uint256 usedExtraFee = (availableDLC * usedDuration) / rentDuration;
            uint256 penaltyExtraFee = (availableDLC * penaltyDuration) / rentDuration;
            uint256 minerExtraFee = usedExtraFee > penaltyExtraFee ? usedExtraFee - penaltyExtraFee : 0;

            // 退给租户：未使用 + 惩罚（全 DLC）
            uint256 payBackDLCFee = (feeInfo.baseFee - usedBaseFee) + (feeInfo.platformFee - usedPlatformFee)
                + (availableDLC - usedExtraFee) + penaltyExtraFee;

            // 防止超出实际余额
            uint256 actualBalance = feeToken.balanceOf(address(this));
            if (payBackDLCFee > actualBalance) { payBackDLCFee = actualBalance; }

            if (payBackDLCFee > 0) {
                SafeERC20.safeTransfer(feeToken, payer, payBackDLCFee);
                emit PayBackFee(machineId, rentId, payer, payBackDLCFee);
            }

            {
                uint256 dlcBal2 = feeToken.balanceOf(address(this));
                uint256 burnAmt2 = usedBaseFee > dlcBal2 ? dlcBal2 : usedBaseFee;
                if (burnAmt2 > 0) {
                    feeToken.approve(address(this), burnAmt2);
                    feeToken.burnFrom(address(this), burnAmt2);
                    emit BurnedFee(machineId, rentId, block.timestamp, burnAmt2, rentInfo.renter, 1);
                    totalBurnedAmount += burnAmt2;
                }
            }

            if (minerExtraFee > 0) {
                uint256 dlcBal3 = feeToken.balanceOf(address(this));
                uint256 transferAmt3 = minerExtraFee > dlcBal3 ? dlcBal3 : minerExtraFee;
                if (transferAmt3 > 0) {
                    SafeERC20.safeTransfer(feeToken, rentInfo.stakeHolder, transferAmt3);
                    emit ExtraRentFeeTransfer(rentInfo.stakeHolder, rentId, transferAmt3);
                }
            }
        }

        {
            uint256 dlcBal4 = feeToken.balanceOf(address(this));
            uint256 platAmt = usedPlatformFee > dlcBal4 ? dlcBal4 : usedPlatformFee;
            if (platAmt > 0) {
                distributePlatformFee(rentId, machineId, platAmt);
            }
        }

        machineId2LastRentEndBlock[machineId] = block.number;
        machine2ProxyRented[machineId] = false;
        delete rentId2RentInfo[rentId];
        delete machineId2RentId[machineId];
        delete machineId2IsMonthlyRent[machineId];
        delete rentId2FeeInfoInDLC[rentId];

        emit EndRentMachine(rentInfo.stakeHolder, rentId, machineId, block.timestamp, rentInfo.renter);
    }

    /// @notice 当机器离线且租赁已过期时，清理租赁状态并处理费用
    /// @dev 租赁已过期（用户已使用完），费用正常分配给机器持有者
    function _cleanupExpiredRentOnOffline(string memory machineId, uint256 rentId, RentInfo memory rentInfo) internal {
        FeeInfo memory feeInfo = rentId2FeeInfoInDLC[rentId];

        // 销毁 baseFee
        if (feeInfo.baseFee > 0) {
            feeToken.approve(address(this), feeInfo.baseFee);
            feeToken.burnFrom(address(this), feeInfo.baseFee);
            emit BurnedFee(machineId, rentId, block.timestamp, feeInfo.baseFee, rentInfo.renter, 1);
            totalBurnedAmount += feeInfo.baseFee;
        }

        // extraFee 转给机器持有者（租赁已完成，不退还）
        if (feeInfo.extraFee > 0) {
            if (!feeInfo.isV1) {
                // V2 (或旧数据默认): extraFee 是 Point Token
                IERC20 pointToken = IERC20(address(0x9b09b4B7a748079DAd5c280dCf66428e48E38Cd6));
                uint256 pointTokenBalance = pointToken.balanceOf(address(this));
                uint256 availablePointToken = feeInfo.extraFee > pointTokenBalance ? pointTokenBalance : feeInfo.extraFee;
                if (availablePointToken > 0) {
                    SafeERC20.safeTransfer(pointToken, rentInfo.stakeHolder, availablePointToken);
                    emit ExtraRentFeeTransfer(rentInfo.stakeHolder, rentId, availablePointToken);
                }
            } else {
                // V1: extraFee 是 DLC
                SafeERC20.safeTransfer(feeToken, rentInfo.stakeHolder, feeInfo.extraFee);
                emit ExtraRentFeeTransfer(rentInfo.stakeHolder, rentId, feeInfo.extraFee);
            }
        }

        // platformFee 分配给平台
        if (feeInfo.platformFee > 0) {
            distributePlatformFee(rentId, machineId, feeInfo.platformFee);
        }

        // 通知 Staking 合约清理状态
        stakingContract.endRentMachineWhenMachineOfflineAfterRentEnd(machineId);

        // 清理 Rent 合约状态
        machineId2LastRentEndBlock[machineId] = block.number;
        machine2ProxyRented[machineId] = false;
        delete rentId2RentInfo[rentId];
        delete machineId2RentId[machineId];
        delete machineId2IsMonthlyRent[machineId];
        delete rentId2FeeInfoInDLC[rentId];

        emit EndRentMachine(rentInfo.stakeHolder, rentId, machineId, rentInfo.rentEndTime, rentInfo.renter);
    }

    /// @notice 强制清理不一致的租赁状态
    /// @dev 用于修复 Rent 合约有租赁记录但 Staking 合约 isRentedByUser 为 false 的情况
    /// @dev 只有租赁到期后才能调用
    function forceCleanupRentInfo(string calldata machineId) external onlyOwner {
        uint256 rentId = machineId2RentId[machineId];
        RentInfo memory rentInfo = rentId2RentInfo[rentId];
        require(rentInfo.renter != address(0), "no rent info to cleanup");
        require(block.timestamp >= rentInfo.rentEndTime, "rent not expired");

        machineId2LastRentEndBlock[machineId] = block.number;
        delete rentId2RentInfo[rentId];
        delete machineId2RentId[machineId];
        delete machineId2IsMonthlyRent[machineId];
        delete rentId2FeeInfoInDLC[rentId];
        machine2ProxyRented[machineId] = false;

        emit EndRentMachine(rentInfo.stakeHolder, rentId, machineId, rentInfo.rentEndTime, rentInfo.renter);
    }

    /// @notice 强制清理 v1 存储残留的租赁状态（跳过 rentEndTime 检查）
    /// @dev v1→v2 升级后 RentInfo 结构体字段错位，rentEndTime 为天文数字导致 forceCleanupRentInfo 无法调用
    function forceCleanupRentInfoByOwner(string calldata machineId) external onlyOwner {
        uint256 rentId = machineId2RentId[machineId];
        RentInfo memory rentInfo = rentId2RentInfo[rentId];
        require(rentInfo.renter != address(0) || rentId != 0, "no rent info to cleanup");

        machineId2LastRentEndBlock[machineId] = block.number;
        delete rentId2RentInfo[rentId];
        delete machineId2RentId[machineId];
        delete machineId2IsMonthlyRent[machineId];
        delete rentId2FeeInfoInDLC[rentId];
        machine2ProxyRented[machineId] = false;

        emit EndRentMachine(rentInfo.stakeHolder, rentId, machineId, rentInfo.rentEndTime, rentInfo.renter);
    }

    function distributePlatformFee(uint256 rentId, string memory machineId, uint256 platformFee) internal {
        (address[] memory beneficiaries, uint256[] memory rates,) = stakingContract.getMachineConfig(machineId);
        for (uint8 i = 0; i < beneficiaries.length; i++) {
            uint256 amount = platformFee * rates[i] / 100;
            SafeERC20.safeTransfer(feeToken, beneficiaries[i], amount);
            emit PlatformFeeTransfer(beneficiaries[i], rentId, amount);
        }
    }
}

