var __create = Object.create;
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __getProtoOf = Object.getPrototypeOf;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __commonJS = (cb, mod) => function __require() {
  return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
};
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key2 of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key2) && key2 !== except)
        __defProp(to, key2, { get: () => from[key2], enumerable: !(desc = __getOwnPropDesc(from, key2)) || desc.enumerable });
  }
  return to;
};
var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
  // If the importer is in node compatibility mode or this is not an ESM
  // file that has been converted to a CommonJS file using a Babel-
  // compatible transform (i.e. "__esModule" has not been set), then set
  // "default" to the CommonJS "module.exports" for node compatibility.
  isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
  mod
));
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// node_modules/flatpickr/dist/l10n/zh.js
var require_zh = __commonJS({
  "node_modules/flatpickr/dist/l10n/zh.js"(exports, module2) {
    (function(global, factory) {
      typeof exports === "object" && typeof module2 !== "undefined" ? factory(exports) : typeof define === "function" && define.amd ? define(["exports"], factory) : (global = typeof globalThis !== "undefined" ? globalThis : global || self, factory(global.zh = {}));
    })(exports, (function(exports2) {
      "use strict";
      var fp = typeof window !== "undefined" && window.flatpickr !== void 0 ? window.flatpickr : {
        l10ns: {}
      };
      var Mandarin2 = {
        weekdays: {
          shorthand: ["\u5468\u65E5", "\u5468\u4E00", "\u5468\u4E8C", "\u5468\u4E09", "\u5468\u56DB", "\u5468\u4E94", "\u5468\u516D"],
          longhand: [
            "\u661F\u671F\u65E5",
            "\u661F\u671F\u4E00",
            "\u661F\u671F\u4E8C",
            "\u661F\u671F\u4E09",
            "\u661F\u671F\u56DB",
            "\u661F\u671F\u4E94",
            "\u661F\u671F\u516D"
          ]
        },
        months: {
          shorthand: [
            "\u4E00\u6708",
            "\u4E8C\u6708",
            "\u4E09\u6708",
            "\u56DB\u6708",
            "\u4E94\u6708",
            "\u516D\u6708",
            "\u4E03\u6708",
            "\u516B\u6708",
            "\u4E5D\u6708",
            "\u5341\u6708",
            "\u5341\u4E00\u6708",
            "\u5341\u4E8C\u6708"
          ],
          longhand: [
            "\u4E00\u6708",
            "\u4E8C\u6708",
            "\u4E09\u6708",
            "\u56DB\u6708",
            "\u4E94\u6708",
            "\u516D\u6708",
            "\u4E03\u6708",
            "\u516B\u6708",
            "\u4E5D\u6708",
            "\u5341\u6708",
            "\u5341\u4E00\u6708",
            "\u5341\u4E8C\u6708"
          ]
        },
        rangeSeparator: " \u81F3 ",
        weekAbbreviation: "\u5468",
        scrollTitle: "\u6EDA\u52A8\u5207\u6362",
        toggleTitle: "\u70B9\u51FB\u5207\u6362 12/24 \u5C0F\u65F6\u65F6\u5236"
      };
      fp.l10ns.zh = Mandarin2;
      var zh = fp.l10ns;
      exports2.Mandarin = Mandarin2;
      exports2.default = zh;
      Object.defineProperty(exports2, "__esModule", { value: true });
    }));
  }
});

// node_modules/base64-js/index.js
var require_base64_js = __commonJS({
  "node_modules/base64-js/index.js"(exports) {
    "use strict";
    exports.byteLength = byteLength;
    exports.toByteArray = toByteArray;
    exports.fromByteArray = fromByteArray;
    var lookup = [];
    var revLookup = [];
    var Arr = typeof Uint8Array !== "undefined" ? Uint8Array : Array;
    var code = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    for (i = 0, len = code.length; i < len; ++i) {
      lookup[i] = code[i];
      revLookup[code.charCodeAt(i)] = i;
    }
    var i;
    var len;
    revLookup["-".charCodeAt(0)] = 62;
    revLookup["_".charCodeAt(0)] = 63;
    function getLens(b64) {
      var len2 = b64.length;
      if (len2 % 4 > 0) {
        throw new Error("Invalid string. Length must be a multiple of 4");
      }
      var validLen = b64.indexOf("=");
      if (validLen === -1) validLen = len2;
      var placeHoldersLen = validLen === len2 ? 0 : 4 - validLen % 4;
      return [validLen, placeHoldersLen];
    }
    function byteLength(b64) {
      var lens = getLens(b64);
      var validLen = lens[0];
      var placeHoldersLen = lens[1];
      return (validLen + placeHoldersLen) * 3 / 4 - placeHoldersLen;
    }
    function _byteLength(b64, validLen, placeHoldersLen) {
      return (validLen + placeHoldersLen) * 3 / 4 - placeHoldersLen;
    }
    function toByteArray(b64) {
      var tmp;
      var lens = getLens(b64);
      var validLen = lens[0];
      var placeHoldersLen = lens[1];
      var arr = new Arr(_byteLength(b64, validLen, placeHoldersLen));
      var curByte = 0;
      var len2 = placeHoldersLen > 0 ? validLen - 4 : validLen;
      var i2;
      for (i2 = 0; i2 < len2; i2 += 4) {
        tmp = revLookup[b64.charCodeAt(i2)] << 18 | revLookup[b64.charCodeAt(i2 + 1)] << 12 | revLookup[b64.charCodeAt(i2 + 2)] << 6 | revLookup[b64.charCodeAt(i2 + 3)];
        arr[curByte++] = tmp >> 16 & 255;
        arr[curByte++] = tmp >> 8 & 255;
        arr[curByte++] = tmp & 255;
      }
      if (placeHoldersLen === 2) {
        tmp = revLookup[b64.charCodeAt(i2)] << 2 | revLookup[b64.charCodeAt(i2 + 1)] >> 4;
        arr[curByte++] = tmp & 255;
      }
      if (placeHoldersLen === 1) {
        tmp = revLookup[b64.charCodeAt(i2)] << 10 | revLookup[b64.charCodeAt(i2 + 1)] << 4 | revLookup[b64.charCodeAt(i2 + 2)] >> 2;
        arr[curByte++] = tmp >> 8 & 255;
        arr[curByte++] = tmp & 255;
      }
      return arr;
    }
    function tripletToBase64(num) {
      return lookup[num >> 18 & 63] + lookup[num >> 12 & 63] + lookup[num >> 6 & 63] + lookup[num & 63];
    }
    function encodeChunk(uint8, start, end) {
      var tmp;
      var output = [];
      for (var i2 = start; i2 < end; i2 += 3) {
        tmp = (uint8[i2] << 16 & 16711680) + (uint8[i2 + 1] << 8 & 65280) + (uint8[i2 + 2] & 255);
        output.push(tripletToBase64(tmp));
      }
      return output.join("");
    }
    function fromByteArray(uint8) {
      var tmp;
      var len2 = uint8.length;
      var extraBytes = len2 % 3;
      var parts = [];
      var maxChunkLength = 16383;
      for (var i2 = 0, len22 = len2 - extraBytes; i2 < len22; i2 += maxChunkLength) {
        parts.push(encodeChunk(uint8, i2, i2 + maxChunkLength > len22 ? len22 : i2 + maxChunkLength));
      }
      if (extraBytes === 1) {
        tmp = uint8[len2 - 1];
        parts.push(
          lookup[tmp >> 2] + lookup[tmp << 4 & 63] + "=="
        );
      } else if (extraBytes === 2) {
        tmp = (uint8[len2 - 2] << 8) + uint8[len2 - 1];
        parts.push(
          lookup[tmp >> 10] + lookup[tmp >> 4 & 63] + lookup[tmp << 2 & 63] + "="
        );
      }
      return parts.join("");
    }
  }
});

// node_modules/ieee754/index.js
var require_ieee754 = __commonJS({
  "node_modules/ieee754/index.js"(exports) {
    exports.read = function(buffer, offset, isLE, mLen, nBytes) {
      var e, m;
      var eLen = nBytes * 8 - mLen - 1;
      var eMax = (1 << eLen) - 1;
      var eBias = eMax >> 1;
      var nBits = -7;
      var i = isLE ? nBytes - 1 : 0;
      var d = isLE ? -1 : 1;
      var s = buffer[offset + i];
      i += d;
      e = s & (1 << -nBits) - 1;
      s >>= -nBits;
      nBits += eLen;
      for (; nBits > 0; e = e * 256 + buffer[offset + i], i += d, nBits -= 8) {
      }
      m = e & (1 << -nBits) - 1;
      e >>= -nBits;
      nBits += mLen;
      for (; nBits > 0; m = m * 256 + buffer[offset + i], i += d, nBits -= 8) {
      }
      if (e === 0) {
        e = 1 - eBias;
      } else if (e === eMax) {
        return m ? NaN : (s ? -1 : 1) * Infinity;
      } else {
        m = m + Math.pow(2, mLen);
        e = e - eBias;
      }
      return (s ? -1 : 1) * m * Math.pow(2, e - mLen);
    };
    exports.write = function(buffer, value, offset, isLE, mLen, nBytes) {
      var e, m, c;
      var eLen = nBytes * 8 - mLen - 1;
      var eMax = (1 << eLen) - 1;
      var eBias = eMax >> 1;
      var rt = mLen === 23 ? Math.pow(2, -24) - Math.pow(2, -77) : 0;
      var i = isLE ? 0 : nBytes - 1;
      var d = isLE ? 1 : -1;
      var s = value < 0 || value === 0 && 1 / value < 0 ? 1 : 0;
      value = Math.abs(value);
      if (isNaN(value) || value === Infinity) {
        m = isNaN(value) ? 1 : 0;
        e = eMax;
      } else {
        e = Math.floor(Math.log(value) / Math.LN2);
        if (value * (c = Math.pow(2, -e)) < 1) {
          e--;
          c *= 2;
        }
        if (e + eBias >= 1) {
          value += rt / c;
        } else {
          value += rt * Math.pow(2, 1 - eBias);
        }
        if (value * c >= 2) {
          e++;
          c /= 2;
        }
        if (e + eBias >= eMax) {
          m = 0;
          e = eMax;
        } else if (e + eBias >= 1) {
          m = (value * c - 1) * Math.pow(2, mLen);
          e = e + eBias;
        } else {
          m = value * Math.pow(2, eBias - 1) * Math.pow(2, mLen);
          e = 0;
        }
      }
      for (; mLen >= 8; buffer[offset + i] = m & 255, i += d, m /= 256, mLen -= 8) {
      }
      e = e << mLen | m;
      eLen += mLen;
      for (; eLen > 0; buffer[offset + i] = e & 255, i += d, e /= 256, eLen -= 8) {
      }
      buffer[offset + i - d] |= s * 128;
    };
  }
});

// node_modules/buffer/index.js
var require_buffer = __commonJS({
  "node_modules/buffer/index.js"(exports) {
    "use strict";
    var base64 = require_base64_js();
    var ieee754 = require_ieee754();
    var customInspectSymbol = typeof Symbol === "function" && typeof Symbol["for"] === "function" ? Symbol["for"]("nodejs.util.inspect.custom") : null;
    exports.Buffer = Buffer3;
    exports.SlowBuffer = SlowBuffer;
    exports.INSPECT_MAX_BYTES = 50;
    var K_MAX_LENGTH = 2147483647;
    exports.kMaxLength = K_MAX_LENGTH;
    Buffer3.TYPED_ARRAY_SUPPORT = typedArraySupport();
    if (!Buffer3.TYPED_ARRAY_SUPPORT && typeof console !== "undefined" && typeof console.error === "function") {
      console.error(
        "This browser lacks typed array (Uint8Array) support which is required by `buffer` v5.x. Use `buffer` v4.x if you require old browser support."
      );
    }
    function typedArraySupport() {
      try {
        const arr = new Uint8Array(1);
        const proto = { foo: function() {
          return 42;
        } };
        Object.setPrototypeOf(proto, Uint8Array.prototype);
        Object.setPrototypeOf(arr, proto);
        return arr.foo() === 42;
      } catch (e) {
        return false;
      }
    }
    Object.defineProperty(Buffer3.prototype, "parent", {
      enumerable: true,
      get: function() {
        if (!Buffer3.isBuffer(this)) return void 0;
        return this.buffer;
      }
    });
    Object.defineProperty(Buffer3.prototype, "offset", {
      enumerable: true,
      get: function() {
        if (!Buffer3.isBuffer(this)) return void 0;
        return this.byteOffset;
      }
    });
    function createBuffer(length) {
      if (length > K_MAX_LENGTH) {
        throw new RangeError('The value "' + length + '" is invalid for option "size"');
      }
      const buf = new Uint8Array(length);
      Object.setPrototypeOf(buf, Buffer3.prototype);
      return buf;
    }
    function Buffer3(arg, encodingOrOffset, length) {
      if (typeof arg === "number") {
        if (typeof encodingOrOffset === "string") {
          throw new TypeError(
            'The "string" argument must be of type string. Received type number'
          );
        }
        return allocUnsafe(arg);
      }
      return from(arg, encodingOrOffset, length);
    }
    Buffer3.poolSize = 8192;
    function from(value, encodingOrOffset, length) {
      if (typeof value === "string") {
        return fromString(value, encodingOrOffset);
      }
      if (ArrayBuffer.isView(value)) {
        return fromArrayView(value);
      }
      if (value == null) {
        throw new TypeError(
          "The first argument must be one of type string, Buffer, ArrayBuffer, Array, or Array-like Object. Received type " + typeof value
        );
      }
      if (isInstance(value, ArrayBuffer) || value && isInstance(value.buffer, ArrayBuffer)) {
        return fromArrayBuffer(value, encodingOrOffset, length);
      }
      if (typeof SharedArrayBuffer !== "undefined" && (isInstance(value, SharedArrayBuffer) || value && isInstance(value.buffer, SharedArrayBuffer))) {
        return fromArrayBuffer(value, encodingOrOffset, length);
      }
      if (typeof value === "number") {
        throw new TypeError(
          'The "value" argument must not be of type number. Received type number'
        );
      }
      const valueOf = value.valueOf && value.valueOf();
      if (valueOf != null && valueOf !== value) {
        return Buffer3.from(valueOf, encodingOrOffset, length);
      }
      const b = fromObject(value);
      if (b) return b;
      if (typeof Symbol !== "undefined" && Symbol.toPrimitive != null && typeof value[Symbol.toPrimitive] === "function") {
        return Buffer3.from(value[Symbol.toPrimitive]("string"), encodingOrOffset, length);
      }
      throw new TypeError(
        "The first argument must be one of type string, Buffer, ArrayBuffer, Array, or Array-like Object. Received type " + typeof value
      );
    }
    Buffer3.from = function(value, encodingOrOffset, length) {
      return from(value, encodingOrOffset, length);
    };
    Object.setPrototypeOf(Buffer3.prototype, Uint8Array.prototype);
    Object.setPrototypeOf(Buffer3, Uint8Array);
    function assertSize(size) {
      if (typeof size !== "number") {
        throw new TypeError('"size" argument must be of type number');
      } else if (size < 0) {
        throw new RangeError('The value "' + size + '" is invalid for option "size"');
      }
    }
    function alloc(size, fill, encoding) {
      assertSize(size);
      if (size <= 0) {
        return createBuffer(size);
      }
      if (fill !== void 0) {
        return typeof encoding === "string" ? createBuffer(size).fill(fill, encoding) : createBuffer(size).fill(fill);
      }
      return createBuffer(size);
    }
    Buffer3.alloc = function(size, fill, encoding) {
      return alloc(size, fill, encoding);
    };
    function allocUnsafe(size) {
      assertSize(size);
      return createBuffer(size < 0 ? 0 : checked(size) | 0);
    }
    Buffer3.allocUnsafe = function(size) {
      return allocUnsafe(size);
    };
    Buffer3.allocUnsafeSlow = function(size) {
      return allocUnsafe(size);
    };
    function fromString(string, encoding) {
      if (typeof encoding !== "string" || encoding === "") {
        encoding = "utf8";
      }
      if (!Buffer3.isEncoding(encoding)) {
        throw new TypeError("Unknown encoding: " + encoding);
      }
      const length = byteLength(string, encoding) | 0;
      let buf = createBuffer(length);
      const actual = buf.write(string, encoding);
      if (actual !== length) {
        buf = buf.slice(0, actual);
      }
      return buf;
    }
    function fromArrayLike(array) {
      const length = array.length < 0 ? 0 : checked(array.length) | 0;
      const buf = createBuffer(length);
      for (let i = 0; i < length; i += 1) {
        buf[i] = array[i] & 255;
      }
      return buf;
    }
    function fromArrayView(arrayView) {
      if (isInstance(arrayView, Uint8Array)) {
        const copy = new Uint8Array(arrayView);
        return fromArrayBuffer(copy.buffer, copy.byteOffset, copy.byteLength);
      }
      return fromArrayLike(arrayView);
    }
    function fromArrayBuffer(array, byteOffset, length) {
      if (byteOffset < 0 || array.byteLength < byteOffset) {
        throw new RangeError('"offset" is outside of buffer bounds');
      }
      if (array.byteLength < byteOffset + (length || 0)) {
        throw new RangeError('"length" is outside of buffer bounds');
      }
      let buf;
      if (byteOffset === void 0 && length === void 0) {
        buf = new Uint8Array(array);
      } else if (length === void 0) {
        buf = new Uint8Array(array, byteOffset);
      } else {
        buf = new Uint8Array(array, byteOffset, length);
      }
      Object.setPrototypeOf(buf, Buffer3.prototype);
      return buf;
    }
    function fromObject(obj) {
      if (Buffer3.isBuffer(obj)) {
        const len = checked(obj.length) | 0;
        const buf = createBuffer(len);
        if (buf.length === 0) {
          return buf;
        }
        obj.copy(buf, 0, 0, len);
        return buf;
      }
      if (obj.length !== void 0) {
        if (typeof obj.length !== "number" || numberIsNaN(obj.length)) {
          return createBuffer(0);
        }
        return fromArrayLike(obj);
      }
      if (obj.type === "Buffer" && Array.isArray(obj.data)) {
        return fromArrayLike(obj.data);
      }
    }
    function checked(length) {
      if (length >= K_MAX_LENGTH) {
        throw new RangeError("Attempt to allocate Buffer larger than maximum size: 0x" + K_MAX_LENGTH.toString(16) + " bytes");
      }
      return length | 0;
    }
    function SlowBuffer(length) {
      if (+length != length) {
        length = 0;
      }
      return Buffer3.alloc(+length);
    }
    Buffer3.isBuffer = function isBuffer(b) {
      return b != null && b._isBuffer === true && b !== Buffer3.prototype;
    };
    Buffer3.compare = function compare(a, b) {
      if (isInstance(a, Uint8Array)) a = Buffer3.from(a, a.offset, a.byteLength);
      if (isInstance(b, Uint8Array)) b = Buffer3.from(b, b.offset, b.byteLength);
      if (!Buffer3.isBuffer(a) || !Buffer3.isBuffer(b)) {
        throw new TypeError(
          'The "buf1", "buf2" arguments must be one of type Buffer or Uint8Array'
        );
      }
      if (a === b) return 0;
      let x = a.length;
      let y = b.length;
      for (let i = 0, len = Math.min(x, y); i < len; ++i) {
        if (a[i] !== b[i]) {
          x = a[i];
          y = b[i];
          break;
        }
      }
      if (x < y) return -1;
      if (y < x) return 1;
      return 0;
    };
    Buffer3.isEncoding = function isEncoding(encoding) {
      switch (String(encoding).toLowerCase()) {
        case "hex":
        case "utf8":
        case "utf-8":
        case "ascii":
        case "latin1":
        case "binary":
        case "base64":
        case "ucs2":
        case "ucs-2":
        case "utf16le":
        case "utf-16le":
          return true;
        default:
          return false;
      }
    };
    Buffer3.concat = function concat(list, length) {
      if (!Array.isArray(list)) {
        throw new TypeError('"list" argument must be an Array of Buffers');
      }
      if (list.length === 0) {
        return Buffer3.alloc(0);
      }
      let i;
      if (length === void 0) {
        length = 0;
        for (i = 0; i < list.length; ++i) {
          length += list[i].length;
        }
      }
      const buffer = Buffer3.allocUnsafe(length);
      let pos = 0;
      for (i = 0; i < list.length; ++i) {
        let buf = list[i];
        if (isInstance(buf, Uint8Array)) {
          if (pos + buf.length > buffer.length) {
            if (!Buffer3.isBuffer(buf)) buf = Buffer3.from(buf);
            buf.copy(buffer, pos);
          } else {
            Uint8Array.prototype.set.call(
              buffer,
              buf,
              pos
            );
          }
        } else if (!Buffer3.isBuffer(buf)) {
          throw new TypeError('"list" argument must be an Array of Buffers');
        } else {
          buf.copy(buffer, pos);
        }
        pos += buf.length;
      }
      return buffer;
    };
    function byteLength(string, encoding) {
      if (Buffer3.isBuffer(string)) {
        return string.length;
      }
      if (ArrayBuffer.isView(string) || isInstance(string, ArrayBuffer)) {
        return string.byteLength;
      }
      if (typeof string !== "string") {
        throw new TypeError(
          'The "string" argument must be one of type string, Buffer, or ArrayBuffer. Received type ' + typeof string
        );
      }
      const len = string.length;
      const mustMatch = arguments.length > 2 && arguments[2] === true;
      if (!mustMatch && len === 0) return 0;
      let loweredCase = false;
      for (; ; ) {
        switch (encoding) {
          case "ascii":
          case "latin1":
          case "binary":
            return len;
          case "utf8":
          case "utf-8":
            return utf8ToBytes(string).length;
          case "ucs2":
          case "ucs-2":
          case "utf16le":
          case "utf-16le":
            return len * 2;
          case "hex":
            return len >>> 1;
          case "base64":
            return base64ToBytes(string).length;
          default:
            if (loweredCase) {
              return mustMatch ? -1 : utf8ToBytes(string).length;
            }
            encoding = ("" + encoding).toLowerCase();
            loweredCase = true;
        }
      }
    }
    Buffer3.byteLength = byteLength;
    function slowToString(encoding, start, end) {
      let loweredCase = false;
      if (start === void 0 || start < 0) {
        start = 0;
      }
      if (start > this.length) {
        return "";
      }
      if (end === void 0 || end > this.length) {
        end = this.length;
      }
      if (end <= 0) {
        return "";
      }
      end >>>= 0;
      start >>>= 0;
      if (end <= start) {
        return "";
      }
      if (!encoding) encoding = "utf8";
      while (true) {
        switch (encoding) {
          case "hex":
            return hexSlice(this, start, end);
          case "utf8":
          case "utf-8":
            return utf8Slice(this, start, end);
          case "ascii":
            return asciiSlice(this, start, end);
          case "latin1":
          case "binary":
            return latin1Slice(this, start, end);
          case "base64":
            return base64Slice(this, start, end);
          case "ucs2":
          case "ucs-2":
          case "utf16le":
          case "utf-16le":
            return utf16leSlice(this, start, end);
          default:
            if (loweredCase) throw new TypeError("Unknown encoding: " + encoding);
            encoding = (encoding + "").toLowerCase();
            loweredCase = true;
        }
      }
    }
    Buffer3.prototype._isBuffer = true;
    function swap(b, n, m) {
      const i = b[n];
      b[n] = b[m];
      b[m] = i;
    }
    Buffer3.prototype.swap16 = function swap16() {
      const len = this.length;
      if (len % 2 !== 0) {
        throw new RangeError("Buffer size must be a multiple of 16-bits");
      }
      for (let i = 0; i < len; i += 2) {
        swap(this, i, i + 1);
      }
      return this;
    };
    Buffer3.prototype.swap32 = function swap32() {
      const len = this.length;
      if (len % 4 !== 0) {
        throw new RangeError("Buffer size must be a multiple of 32-bits");
      }
      for (let i = 0; i < len; i += 4) {
        swap(this, i, i + 3);
        swap(this, i + 1, i + 2);
      }
      return this;
    };
    Buffer3.prototype.swap64 = function swap64() {
      const len = this.length;
      if (len % 8 !== 0) {
        throw new RangeError("Buffer size must be a multiple of 64-bits");
      }
      for (let i = 0; i < len; i += 8) {
        swap(this, i, i + 7);
        swap(this, i + 1, i + 6);
        swap(this, i + 2, i + 5);
        swap(this, i + 3, i + 4);
      }
      return this;
    };
    Buffer3.prototype.toString = function toString() {
      const length = this.length;
      if (length === 0) return "";
      if (arguments.length === 0) return utf8Slice(this, 0, length);
      return slowToString.apply(this, arguments);
    };
    Buffer3.prototype.toLocaleString = Buffer3.prototype.toString;
    Buffer3.prototype.equals = function equals(b) {
      if (!Buffer3.isBuffer(b)) throw new TypeError("Argument must be a Buffer");
      if (this === b) return true;
      return Buffer3.compare(this, b) === 0;
    };
    Buffer3.prototype.inspect = function inspect() {
      let str = "";
      const max = exports.INSPECT_MAX_BYTES;
      str = this.toString("hex", 0, max).replace(/(.{2})/g, "$1 ").trim();
      if (this.length > max) str += " ... ";
      return "<Buffer " + str + ">";
    };
    if (customInspectSymbol) {
      Buffer3.prototype[customInspectSymbol] = Buffer3.prototype.inspect;
    }
    Buffer3.prototype.compare = function compare(target, start, end, thisStart, thisEnd) {
      if (isInstance(target, Uint8Array)) {
        target = Buffer3.from(target, target.offset, target.byteLength);
      }
      if (!Buffer3.isBuffer(target)) {
        throw new TypeError(
          'The "target" argument must be one of type Buffer or Uint8Array. Received type ' + typeof target
        );
      }
      if (start === void 0) {
        start = 0;
      }
      if (end === void 0) {
        end = target ? target.length : 0;
      }
      if (thisStart === void 0) {
        thisStart = 0;
      }
      if (thisEnd === void 0) {
        thisEnd = this.length;
      }
      if (start < 0 || end > target.length || thisStart < 0 || thisEnd > this.length) {
        throw new RangeError("out of range index");
      }
      if (thisStart >= thisEnd && start >= end) {
        return 0;
      }
      if (thisStart >= thisEnd) {
        return -1;
      }
      if (start >= end) {
        return 1;
      }
      start >>>= 0;
      end >>>= 0;
      thisStart >>>= 0;
      thisEnd >>>= 0;
      if (this === target) return 0;
      let x = thisEnd - thisStart;
      let y = end - start;
      const len = Math.min(x, y);
      const thisCopy = this.slice(thisStart, thisEnd);
      const targetCopy = target.slice(start, end);
      for (let i = 0; i < len; ++i) {
        if (thisCopy[i] !== targetCopy[i]) {
          x = thisCopy[i];
          y = targetCopy[i];
          break;
        }
      }
      if (x < y) return -1;
      if (y < x) return 1;
      return 0;
    };
    function bidirectionalIndexOf(buffer, val, byteOffset, encoding, dir) {
      if (buffer.length === 0) return -1;
      if (typeof byteOffset === "string") {
        encoding = byteOffset;
        byteOffset = 0;
      } else if (byteOffset > 2147483647) {
        byteOffset = 2147483647;
      } else if (byteOffset < -2147483648) {
        byteOffset = -2147483648;
      }
      byteOffset = +byteOffset;
      if (numberIsNaN(byteOffset)) {
        byteOffset = dir ? 0 : buffer.length - 1;
      }
      if (byteOffset < 0) byteOffset = buffer.length + byteOffset;
      if (byteOffset >= buffer.length) {
        if (dir) return -1;
        else byteOffset = buffer.length - 1;
      } else if (byteOffset < 0) {
        if (dir) byteOffset = 0;
        else return -1;
      }
      if (typeof val === "string") {
        val = Buffer3.from(val, encoding);
      }
      if (Buffer3.isBuffer(val)) {
        if (val.length === 0) {
          return -1;
        }
        return arrayIndexOf(buffer, val, byteOffset, encoding, dir);
      } else if (typeof val === "number") {
        val = val & 255;
        if (typeof Uint8Array.prototype.indexOf === "function") {
          if (dir) {
            return Uint8Array.prototype.indexOf.call(buffer, val, byteOffset);
          } else {
            return Uint8Array.prototype.lastIndexOf.call(buffer, val, byteOffset);
          }
        }
        return arrayIndexOf(buffer, [val], byteOffset, encoding, dir);
      }
      throw new TypeError("val must be string, number or Buffer");
    }
    function arrayIndexOf(arr, val, byteOffset, encoding, dir) {
      let indexSize = 1;
      let arrLength = arr.length;
      let valLength = val.length;
      if (encoding !== void 0) {
        encoding = String(encoding).toLowerCase();
        if (encoding === "ucs2" || encoding === "ucs-2" || encoding === "utf16le" || encoding === "utf-16le") {
          if (arr.length < 2 || val.length < 2) {
            return -1;
          }
          indexSize = 2;
          arrLength /= 2;
          valLength /= 2;
          byteOffset /= 2;
        }
      }
      function read(buf, i2) {
        if (indexSize === 1) {
          return buf[i2];
        } else {
          return buf.readUInt16BE(i2 * indexSize);
        }
      }
      let i;
      if (dir) {
        let foundIndex = -1;
        for (i = byteOffset; i < arrLength; i++) {
          if (read(arr, i) === read(val, foundIndex === -1 ? 0 : i - foundIndex)) {
            if (foundIndex === -1) foundIndex = i;
            if (i - foundIndex + 1 === valLength) return foundIndex * indexSize;
          } else {
            if (foundIndex !== -1) i -= i - foundIndex;
            foundIndex = -1;
          }
        }
      } else {
        if (byteOffset + valLength > arrLength) byteOffset = arrLength - valLength;
        for (i = byteOffset; i >= 0; i--) {
          let found = true;
          for (let j = 0; j < valLength; j++) {
            if (read(arr, i + j) !== read(val, j)) {
              found = false;
              break;
            }
          }
          if (found) return i;
        }
      }
      return -1;
    }
    Buffer3.prototype.includes = function includes(val, byteOffset, encoding) {
      return this.indexOf(val, byteOffset, encoding) !== -1;
    };
    Buffer3.prototype.indexOf = function indexOf(val, byteOffset, encoding) {
      return bidirectionalIndexOf(this, val, byteOffset, encoding, true);
    };
    Buffer3.prototype.lastIndexOf = function lastIndexOf(val, byteOffset, encoding) {
      return bidirectionalIndexOf(this, val, byteOffset, encoding, false);
    };
    function hexWrite(buf, string, offset, length) {
      offset = Number(offset) || 0;
      const remaining = buf.length - offset;
      if (!length) {
        length = remaining;
      } else {
        length = Number(length);
        if (length > remaining) {
          length = remaining;
        }
      }
      const strLen = string.length;
      if (length > strLen / 2) {
        length = strLen / 2;
      }
      let i;
      for (i = 0; i < length; ++i) {
        const parsed = parseInt(string.substr(i * 2, 2), 16);
        if (numberIsNaN(parsed)) return i;
        buf[offset + i] = parsed;
      }
      return i;
    }
    function utf8Write(buf, string, offset, length) {
      return blitBuffer(utf8ToBytes(string, buf.length - offset), buf, offset, length);
    }
    function asciiWrite(buf, string, offset, length) {
      return blitBuffer(asciiToBytes(string), buf, offset, length);
    }
    function base64Write(buf, string, offset, length) {
      return blitBuffer(base64ToBytes(string), buf, offset, length);
    }
    function ucs2Write(buf, string, offset, length) {
      return blitBuffer(utf16leToBytes(string, buf.length - offset), buf, offset, length);
    }
    Buffer3.prototype.write = function write(string, offset, length, encoding) {
      if (offset === void 0) {
        encoding = "utf8";
        length = this.length;
        offset = 0;
      } else if (length === void 0 && typeof offset === "string") {
        encoding = offset;
        length = this.length;
        offset = 0;
      } else if (isFinite(offset)) {
        offset = offset >>> 0;
        if (isFinite(length)) {
          length = length >>> 0;
          if (encoding === void 0) encoding = "utf8";
        } else {
          encoding = length;
          length = void 0;
        }
      } else {
        throw new Error(
          "Buffer.write(string, encoding, offset[, length]) is no longer supported"
        );
      }
      const remaining = this.length - offset;
      if (length === void 0 || length > remaining) length = remaining;
      if (string.length > 0 && (length < 0 || offset < 0) || offset > this.length) {
        throw new RangeError("Attempt to write outside buffer bounds");
      }
      if (!encoding) encoding = "utf8";
      let loweredCase = false;
      for (; ; ) {
        switch (encoding) {
          case "hex":
            return hexWrite(this, string, offset, length);
          case "utf8":
          case "utf-8":
            return utf8Write(this, string, offset, length);
          case "ascii":
          case "latin1":
          case "binary":
            return asciiWrite(this, string, offset, length);
          case "base64":
            return base64Write(this, string, offset, length);
          case "ucs2":
          case "ucs-2":
          case "utf16le":
          case "utf-16le":
            return ucs2Write(this, string, offset, length);
          default:
            if (loweredCase) throw new TypeError("Unknown encoding: " + encoding);
            encoding = ("" + encoding).toLowerCase();
            loweredCase = true;
        }
      }
    };
    Buffer3.prototype.toJSON = function toJSON() {
      return {
        type: "Buffer",
        data: Array.prototype.slice.call(this._arr || this, 0)
      };
    };
    function base64Slice(buf, start, end) {
      if (start === 0 && end === buf.length) {
        return base64.fromByteArray(buf);
      } else {
        return base64.fromByteArray(buf.slice(start, end));
      }
    }
    function utf8Slice(buf, start, end) {
      end = Math.min(buf.length, end);
      const res = [];
      let i = start;
      while (i < end) {
        const firstByte = buf[i];
        let codePoint = null;
        let bytesPerSequence = firstByte > 239 ? 4 : firstByte > 223 ? 3 : firstByte > 191 ? 2 : 1;
        if (i + bytesPerSequence <= end) {
          let secondByte, thirdByte, fourthByte, tempCodePoint;
          switch (bytesPerSequence) {
            case 1:
              if (firstByte < 128) {
                codePoint = firstByte;
              }
              break;
            case 2:
              secondByte = buf[i + 1];
              if ((secondByte & 192) === 128) {
                tempCodePoint = (firstByte & 31) << 6 | secondByte & 63;
                if (tempCodePoint > 127) {
                  codePoint = tempCodePoint;
                }
              }
              break;
            case 3:
              secondByte = buf[i + 1];
              thirdByte = buf[i + 2];
              if ((secondByte & 192) === 128 && (thirdByte & 192) === 128) {
                tempCodePoint = (firstByte & 15) << 12 | (secondByte & 63) << 6 | thirdByte & 63;
                if (tempCodePoint > 2047 && (tempCodePoint < 55296 || tempCodePoint > 57343)) {
                  codePoint = tempCodePoint;
                }
              }
              break;
            case 4:
              secondByte = buf[i + 1];
              thirdByte = buf[i + 2];
              fourthByte = buf[i + 3];
              if ((secondByte & 192) === 128 && (thirdByte & 192) === 128 && (fourthByte & 192) === 128) {
                tempCodePoint = (firstByte & 15) << 18 | (secondByte & 63) << 12 | (thirdByte & 63) << 6 | fourthByte & 63;
                if (tempCodePoint > 65535 && tempCodePoint < 1114112) {
                  codePoint = tempCodePoint;
                }
              }
          }
        }
        if (codePoint === null) {
          codePoint = 65533;
          bytesPerSequence = 1;
        } else if (codePoint > 65535) {
          codePoint -= 65536;
          res.push(codePoint >>> 10 & 1023 | 55296);
          codePoint = 56320 | codePoint & 1023;
        }
        res.push(codePoint);
        i += bytesPerSequence;
      }
      return decodeCodePointsArray(res);
    }
    var MAX_ARGUMENTS_LENGTH = 4096;
    function decodeCodePointsArray(codePoints) {
      const len = codePoints.length;
      if (len <= MAX_ARGUMENTS_LENGTH) {
        return String.fromCharCode.apply(String, codePoints);
      }
      let res = "";
      let i = 0;
      while (i < len) {
        res += String.fromCharCode.apply(
          String,
          codePoints.slice(i, i += MAX_ARGUMENTS_LENGTH)
        );
      }
      return res;
    }
    function asciiSlice(buf, start, end) {
      let ret = "";
      end = Math.min(buf.length, end);
      for (let i = start; i < end; ++i) {
        ret += String.fromCharCode(buf[i] & 127);
      }
      return ret;
    }
    function latin1Slice(buf, start, end) {
      let ret = "";
      end = Math.min(buf.length, end);
      for (let i = start; i < end; ++i) {
        ret += String.fromCharCode(buf[i]);
      }
      return ret;
    }
    function hexSlice(buf, start, end) {
      const len = buf.length;
      if (!start || start < 0) start = 0;
      if (!end || end < 0 || end > len) end = len;
      let out = "";
      for (let i = start; i < end; ++i) {
        out += hexSliceLookupTable[buf[i]];
      }
      return out;
    }
    function utf16leSlice(buf, start, end) {
      const bytes = buf.slice(start, end);
      let res = "";
      for (let i = 0; i < bytes.length - 1; i += 2) {
        res += String.fromCharCode(bytes[i] + bytes[i + 1] * 256);
      }
      return res;
    }
    Buffer3.prototype.slice = function slice(start, end) {
      const len = this.length;
      start = ~~start;
      end = end === void 0 ? len : ~~end;
      if (start < 0) {
        start += len;
        if (start < 0) start = 0;
      } else if (start > len) {
        start = len;
      }
      if (end < 0) {
        end += len;
        if (end < 0) end = 0;
      } else if (end > len) {
        end = len;
      }
      if (end < start) end = start;
      const newBuf = this.subarray(start, end);
      Object.setPrototypeOf(newBuf, Buffer3.prototype);
      return newBuf;
    };
    function checkOffset(offset, ext, length) {
      if (offset % 1 !== 0 || offset < 0) throw new RangeError("offset is not uint");
      if (offset + ext > length) throw new RangeError("Trying to access beyond buffer length");
    }
    Buffer3.prototype.readUintLE = Buffer3.prototype.readUIntLE = function readUIntLE(offset, byteLength2, noAssert) {
      offset = offset >>> 0;
      byteLength2 = byteLength2 >>> 0;
      if (!noAssert) checkOffset(offset, byteLength2, this.length);
      let val = this[offset];
      let mul = 1;
      let i = 0;
      while (++i < byteLength2 && (mul *= 256)) {
        val += this[offset + i] * mul;
      }
      return val;
    };
    Buffer3.prototype.readUintBE = Buffer3.prototype.readUIntBE = function readUIntBE(offset, byteLength2, noAssert) {
      offset = offset >>> 0;
      byteLength2 = byteLength2 >>> 0;
      if (!noAssert) {
        checkOffset(offset, byteLength2, this.length);
      }
      let val = this[offset + --byteLength2];
      let mul = 1;
      while (byteLength2 > 0 && (mul *= 256)) {
        val += this[offset + --byteLength2] * mul;
      }
      return val;
    };
    Buffer3.prototype.readUint8 = Buffer3.prototype.readUInt8 = function readUInt8(offset, noAssert) {
      offset = offset >>> 0;
      if (!noAssert) checkOffset(offset, 1, this.length);
      return this[offset];
    };
    Buffer3.prototype.readUint16LE = Buffer3.prototype.readUInt16LE = function readUInt16LE(offset, noAssert) {
      offset = offset >>> 0;
      if (!noAssert) checkOffset(offset, 2, this.length);
      return this[offset] | this[offset + 1] << 8;
    };
    Buffer3.prototype.readUint16BE = Buffer3.prototype.readUInt16BE = function readUInt16BE(offset, noAssert) {
      offset = offset >>> 0;
      if (!noAssert) checkOffset(offset, 2, this.length);
      return this[offset] << 8 | this[offset + 1];
    };
    Buffer3.prototype.readUint32LE = Buffer3.prototype.readUInt32LE = function readUInt32LE(offset, noAssert) {
      offset = offset >>> 0;
      if (!noAssert) checkOffset(offset, 4, this.length);
      return (this[offset] | this[offset + 1] << 8 | this[offset + 2] << 16) + this[offset + 3] * 16777216;
    };
    Buffer3.prototype.readUint32BE = Buffer3.prototype.readUInt32BE = function readUInt32BE(offset, noAssert) {
      offset = offset >>> 0;
      if (!noAssert) checkOffset(offset, 4, this.length);
      return this[offset] * 16777216 + (this[offset + 1] << 16 | this[offset + 2] << 8 | this[offset + 3]);
    };
    Buffer3.prototype.readBigUInt64LE = defineBigIntMethod(function readBigUInt64LE(offset) {
      offset = offset >>> 0;
      validateNumber(offset, "offset");
      const first = this[offset];
      const last = this[offset + 7];
      if (first === void 0 || last === void 0) {
        boundsError(offset, this.length - 8);
      }
      const lo = first + this[++offset] * 2 ** 8 + this[++offset] * 2 ** 16 + this[++offset] * 2 ** 24;
      const hi = this[++offset] + this[++offset] * 2 ** 8 + this[++offset] * 2 ** 16 + last * 2 ** 24;
      return BigInt(lo) + (BigInt(hi) << BigInt(32));
    });
    Buffer3.prototype.readBigUInt64BE = defineBigIntMethod(function readBigUInt64BE(offset) {
      offset = offset >>> 0;
      validateNumber(offset, "offset");
      const first = this[offset];
      const last = this[offset + 7];
      if (first === void 0 || last === void 0) {
        boundsError(offset, this.length - 8);
      }
      const hi = first * 2 ** 24 + this[++offset] * 2 ** 16 + this[++offset] * 2 ** 8 + this[++offset];
      const lo = this[++offset] * 2 ** 24 + this[++offset] * 2 ** 16 + this[++offset] * 2 ** 8 + last;
      return (BigInt(hi) << BigInt(32)) + BigInt(lo);
    });
    Buffer3.prototype.readIntLE = function readIntLE(offset, byteLength2, noAssert) {
      offset = offset >>> 0;
      byteLength2 = byteLength2 >>> 0;
      if (!noAssert) checkOffset(offset, byteLength2, this.length);
      let val = this[offset];
      let mul = 1;
      let i = 0;
      while (++i < byteLength2 && (mul *= 256)) {
        val += this[offset + i] * mul;
      }
      mul *= 128;
      if (val >= mul) val -= Math.pow(2, 8 * byteLength2);
      return val;
    };
    Buffer3.prototype.readIntBE = function readIntBE(offset, byteLength2, noAssert) {
      offset = offset >>> 0;
      byteLength2 = byteLength2 >>> 0;
      if (!noAssert) checkOffset(offset, byteLength2, this.length);
      let i = byteLength2;
      let mul = 1;
      let val = this[offset + --i];
      while (i > 0 && (mul *= 256)) {
        val += this[offset + --i] * mul;
      }
      mul *= 128;
      if (val >= mul) val -= Math.pow(2, 8 * byteLength2);
      return val;
    };
    Buffer3.prototype.readInt8 = function readInt8(offset, noAssert) {
      offset = offset >>> 0;
      if (!noAssert) checkOffset(offset, 1, this.length);
      if (!(this[offset] & 128)) return this[offset];
      return (255 - this[offset] + 1) * -1;
    };
    Buffer3.prototype.readInt16LE = function readInt16LE(offset, noAssert) {
      offset = offset >>> 0;
      if (!noAssert) checkOffset(offset, 2, this.length);
      const val = this[offset] | this[offset + 1] << 8;
      return val & 32768 ? val | 4294901760 : val;
    };
    Buffer3.prototype.readInt16BE = function readInt16BE(offset, noAssert) {
      offset = offset >>> 0;
      if (!noAssert) checkOffset(offset, 2, this.length);
      const val = this[offset + 1] | this[offset] << 8;
      return val & 32768 ? val | 4294901760 : val;
    };
    Buffer3.prototype.readInt32LE = function readInt32LE(offset, noAssert) {
      offset = offset >>> 0;
      if (!noAssert) checkOffset(offset, 4, this.length);
      return this[offset] | this[offset + 1] << 8 | this[offset + 2] << 16 | this[offset + 3] << 24;
    };
    Buffer3.prototype.readInt32BE = function readInt32BE(offset, noAssert) {
      offset = offset >>> 0;
      if (!noAssert) checkOffset(offset, 4, this.length);
      return this[offset] << 24 | this[offset + 1] << 16 | this[offset + 2] << 8 | this[offset + 3];
    };
    Buffer3.prototype.readBigInt64LE = defineBigIntMethod(function readBigInt64LE(offset) {
      offset = offset >>> 0;
      validateNumber(offset, "offset");
      const first = this[offset];
      const last = this[offset + 7];
      if (first === void 0 || last === void 0) {
        boundsError(offset, this.length - 8);
      }
      const val = this[offset + 4] + this[offset + 5] * 2 ** 8 + this[offset + 6] * 2 ** 16 + (last << 24);
      return (BigInt(val) << BigInt(32)) + BigInt(first + this[++offset] * 2 ** 8 + this[++offset] * 2 ** 16 + this[++offset] * 2 ** 24);
    });
    Buffer3.prototype.readBigInt64BE = defineBigIntMethod(function readBigInt64BE(offset) {
      offset = offset >>> 0;
      validateNumber(offset, "offset");
      const first = this[offset];
      const last = this[offset + 7];
      if (first === void 0 || last === void 0) {
        boundsError(offset, this.length - 8);
      }
      const val = (first << 24) + // Overflow
      this[++offset] * 2 ** 16 + this[++offset] * 2 ** 8 + this[++offset];
      return (BigInt(val) << BigInt(32)) + BigInt(this[++offset] * 2 ** 24 + this[++offset] * 2 ** 16 + this[++offset] * 2 ** 8 + last);
    });
    Buffer3.prototype.readFloatLE = function readFloatLE(offset, noAssert) {
      offset = offset >>> 0;
      if (!noAssert) checkOffset(offset, 4, this.length);
      return ieee754.read(this, offset, true, 23, 4);
    };
    Buffer3.prototype.readFloatBE = function readFloatBE(offset, noAssert) {
      offset = offset >>> 0;
      if (!noAssert) checkOffset(offset, 4, this.length);
      return ieee754.read(this, offset, false, 23, 4);
    };
    Buffer3.prototype.readDoubleLE = function readDoubleLE(offset, noAssert) {
      offset = offset >>> 0;
      if (!noAssert) checkOffset(offset, 8, this.length);
      return ieee754.read(this, offset, true, 52, 8);
    };
    Buffer3.prototype.readDoubleBE = function readDoubleBE(offset, noAssert) {
      offset = offset >>> 0;
      if (!noAssert) checkOffset(offset, 8, this.length);
      return ieee754.read(this, offset, false, 52, 8);
    };
    function checkInt(buf, value, offset, ext, max, min) {
      if (!Buffer3.isBuffer(buf)) throw new TypeError('"buffer" argument must be a Buffer instance');
      if (value > max || value < min) throw new RangeError('"value" argument is out of bounds');
      if (offset + ext > buf.length) throw new RangeError("Index out of range");
    }
    Buffer3.prototype.writeUintLE = Buffer3.prototype.writeUIntLE = function writeUIntLE(value, offset, byteLength2, noAssert) {
      value = +value;
      offset = offset >>> 0;
      byteLength2 = byteLength2 >>> 0;
      if (!noAssert) {
        const maxBytes = Math.pow(2, 8 * byteLength2) - 1;
        checkInt(this, value, offset, byteLength2, maxBytes, 0);
      }
      let mul = 1;
      let i = 0;
      this[offset] = value & 255;
      while (++i < byteLength2 && (mul *= 256)) {
        this[offset + i] = value / mul & 255;
      }
      return offset + byteLength2;
    };
    Buffer3.prototype.writeUintBE = Buffer3.prototype.writeUIntBE = function writeUIntBE(value, offset, byteLength2, noAssert) {
      value = +value;
      offset = offset >>> 0;
      byteLength2 = byteLength2 >>> 0;
      if (!noAssert) {
        const maxBytes = Math.pow(2, 8 * byteLength2) - 1;
        checkInt(this, value, offset, byteLength2, maxBytes, 0);
      }
      let i = byteLength2 - 1;
      let mul = 1;
      this[offset + i] = value & 255;
      while (--i >= 0 && (mul *= 256)) {
        this[offset + i] = value / mul & 255;
      }
      return offset + byteLength2;
    };
    Buffer3.prototype.writeUint8 = Buffer3.prototype.writeUInt8 = function writeUInt8(value, offset, noAssert) {
      value = +value;
      offset = offset >>> 0;
      if (!noAssert) checkInt(this, value, offset, 1, 255, 0);
      this[offset] = value & 255;
      return offset + 1;
    };
    Buffer3.prototype.writeUint16LE = Buffer3.prototype.writeUInt16LE = function writeUInt16LE(value, offset, noAssert) {
      value = +value;
      offset = offset >>> 0;
      if (!noAssert) checkInt(this, value, offset, 2, 65535, 0);
      this[offset] = value & 255;
      this[offset + 1] = value >>> 8;
      return offset + 2;
    };
    Buffer3.prototype.writeUint16BE = Buffer3.prototype.writeUInt16BE = function writeUInt16BE(value, offset, noAssert) {
      value = +value;
      offset = offset >>> 0;
      if (!noAssert) checkInt(this, value, offset, 2, 65535, 0);
      this[offset] = value >>> 8;
      this[offset + 1] = value & 255;
      return offset + 2;
    };
    Buffer3.prototype.writeUint32LE = Buffer3.prototype.writeUInt32LE = function writeUInt32LE(value, offset, noAssert) {
      value = +value;
      offset = offset >>> 0;
      if (!noAssert) checkInt(this, value, offset, 4, 4294967295, 0);
      this[offset + 3] = value >>> 24;
      this[offset + 2] = value >>> 16;
      this[offset + 1] = value >>> 8;
      this[offset] = value & 255;
      return offset + 4;
    };
    Buffer3.prototype.writeUint32BE = Buffer3.prototype.writeUInt32BE = function writeUInt32BE(value, offset, noAssert) {
      value = +value;
      offset = offset >>> 0;
      if (!noAssert) checkInt(this, value, offset, 4, 4294967295, 0);
      this[offset] = value >>> 24;
      this[offset + 1] = value >>> 16;
      this[offset + 2] = value >>> 8;
      this[offset + 3] = value & 255;
      return offset + 4;
    };
    function wrtBigUInt64LE(buf, value, offset, min, max) {
      checkIntBI(value, min, max, buf, offset, 7);
      let lo = Number(value & BigInt(4294967295));
      buf[offset++] = lo;
      lo = lo >> 8;
      buf[offset++] = lo;
      lo = lo >> 8;
      buf[offset++] = lo;
      lo = lo >> 8;
      buf[offset++] = lo;
      let hi = Number(value >> BigInt(32) & BigInt(4294967295));
      buf[offset++] = hi;
      hi = hi >> 8;
      buf[offset++] = hi;
      hi = hi >> 8;
      buf[offset++] = hi;
      hi = hi >> 8;
      buf[offset++] = hi;
      return offset;
    }
    function wrtBigUInt64BE(buf, value, offset, min, max) {
      checkIntBI(value, min, max, buf, offset, 7);
      let lo = Number(value & BigInt(4294967295));
      buf[offset + 7] = lo;
      lo = lo >> 8;
      buf[offset + 6] = lo;
      lo = lo >> 8;
      buf[offset + 5] = lo;
      lo = lo >> 8;
      buf[offset + 4] = lo;
      let hi = Number(value >> BigInt(32) & BigInt(4294967295));
      buf[offset + 3] = hi;
      hi = hi >> 8;
      buf[offset + 2] = hi;
      hi = hi >> 8;
      buf[offset + 1] = hi;
      hi = hi >> 8;
      buf[offset] = hi;
      return offset + 8;
    }
    Buffer3.prototype.writeBigUInt64LE = defineBigIntMethod(function writeBigUInt64LE(value, offset = 0) {
      return wrtBigUInt64LE(this, value, offset, BigInt(0), BigInt("0xffffffffffffffff"));
    });
    Buffer3.prototype.writeBigUInt64BE = defineBigIntMethod(function writeBigUInt64BE(value, offset = 0) {
      return wrtBigUInt64BE(this, value, offset, BigInt(0), BigInt("0xffffffffffffffff"));
    });
    Buffer3.prototype.writeIntLE = function writeIntLE(value, offset, byteLength2, noAssert) {
      value = +value;
      offset = offset >>> 0;
      if (!noAssert) {
        const limit = Math.pow(2, 8 * byteLength2 - 1);
        checkInt(this, value, offset, byteLength2, limit - 1, -limit);
      }
      let i = 0;
      let mul = 1;
      let sub = 0;
      this[offset] = value & 255;
      while (++i < byteLength2 && (mul *= 256)) {
        if (value < 0 && sub === 0 && this[offset + i - 1] !== 0) {
          sub = 1;
        }
        this[offset + i] = (value / mul >> 0) - sub & 255;
      }
      return offset + byteLength2;
    };
    Buffer3.prototype.writeIntBE = function writeIntBE(value, offset, byteLength2, noAssert) {
      value = +value;
      offset = offset >>> 0;
      if (!noAssert) {
        const limit = Math.pow(2, 8 * byteLength2 - 1);
        checkInt(this, value, offset, byteLength2, limit - 1, -limit);
      }
      let i = byteLength2 - 1;
      let mul = 1;
      let sub = 0;
      this[offset + i] = value & 255;
      while (--i >= 0 && (mul *= 256)) {
        if (value < 0 && sub === 0 && this[offset + i + 1] !== 0) {
          sub = 1;
        }
        this[offset + i] = (value / mul >> 0) - sub & 255;
      }
      return offset + byteLength2;
    };
    Buffer3.prototype.writeInt8 = function writeInt8(value, offset, noAssert) {
      value = +value;
      offset = offset >>> 0;
      if (!noAssert) checkInt(this, value, offset, 1, 127, -128);
      if (value < 0) value = 255 + value + 1;
      this[offset] = value & 255;
      return offset + 1;
    };
    Buffer3.prototype.writeInt16LE = function writeInt16LE(value, offset, noAssert) {
      value = +value;
      offset = offset >>> 0;
      if (!noAssert) checkInt(this, value, offset, 2, 32767, -32768);
      this[offset] = value & 255;
      this[offset + 1] = value >>> 8;
      return offset + 2;
    };
    Buffer3.prototype.writeInt16BE = function writeInt16BE(value, offset, noAssert) {
      value = +value;
      offset = offset >>> 0;
      if (!noAssert) checkInt(this, value, offset, 2, 32767, -32768);
      this[offset] = value >>> 8;
      this[offset + 1] = value & 255;
      return offset + 2;
    };
    Buffer3.prototype.writeInt32LE = function writeInt32LE(value, offset, noAssert) {
      value = +value;
      offset = offset >>> 0;
      if (!noAssert) checkInt(this, value, offset, 4, 2147483647, -2147483648);
      this[offset] = value & 255;
      this[offset + 1] = value >>> 8;
      this[offset + 2] = value >>> 16;
      this[offset + 3] = value >>> 24;
      return offset + 4;
    };
    Buffer3.prototype.writeInt32BE = function writeInt32BE(value, offset, noAssert) {
      value = +value;
      offset = offset >>> 0;
      if (!noAssert) checkInt(this, value, offset, 4, 2147483647, -2147483648);
      if (value < 0) value = 4294967295 + value + 1;
      this[offset] = value >>> 24;
      this[offset + 1] = value >>> 16;
      this[offset + 2] = value >>> 8;
      this[offset + 3] = value & 255;
      return offset + 4;
    };
    Buffer3.prototype.writeBigInt64LE = defineBigIntMethod(function writeBigInt64LE(value, offset = 0) {
      return wrtBigUInt64LE(this, value, offset, -BigInt("0x8000000000000000"), BigInt("0x7fffffffffffffff"));
    });
    Buffer3.prototype.writeBigInt64BE = defineBigIntMethod(function writeBigInt64BE(value, offset = 0) {
      return wrtBigUInt64BE(this, value, offset, -BigInt("0x8000000000000000"), BigInt("0x7fffffffffffffff"));
    });
    function checkIEEE754(buf, value, offset, ext, max, min) {
      if (offset + ext > buf.length) throw new RangeError("Index out of range");
      if (offset < 0) throw new RangeError("Index out of range");
    }
    function writeFloat(buf, value, offset, littleEndian, noAssert) {
      value = +value;
      offset = offset >>> 0;
      if (!noAssert) {
        checkIEEE754(buf, value, offset, 4, 34028234663852886e22, -34028234663852886e22);
      }
      ieee754.write(buf, value, offset, littleEndian, 23, 4);
      return offset + 4;
    }
    Buffer3.prototype.writeFloatLE = function writeFloatLE(value, offset, noAssert) {
      return writeFloat(this, value, offset, true, noAssert);
    };
    Buffer3.prototype.writeFloatBE = function writeFloatBE(value, offset, noAssert) {
      return writeFloat(this, value, offset, false, noAssert);
    };
    function writeDouble(buf, value, offset, littleEndian, noAssert) {
      value = +value;
      offset = offset >>> 0;
      if (!noAssert) {
        checkIEEE754(buf, value, offset, 8, 17976931348623157e292, -17976931348623157e292);
      }
      ieee754.write(buf, value, offset, littleEndian, 52, 8);
      return offset + 8;
    }
    Buffer3.prototype.writeDoubleLE = function writeDoubleLE(value, offset, noAssert) {
      return writeDouble(this, value, offset, true, noAssert);
    };
    Buffer3.prototype.writeDoubleBE = function writeDoubleBE(value, offset, noAssert) {
      return writeDouble(this, value, offset, false, noAssert);
    };
    Buffer3.prototype.copy = function copy(target, targetStart, start, end) {
      if (!Buffer3.isBuffer(target)) throw new TypeError("argument should be a Buffer");
      if (!start) start = 0;
      if (!end && end !== 0) end = this.length;
      if (targetStart >= target.length) targetStart = target.length;
      if (!targetStart) targetStart = 0;
      if (end > 0 && end < start) end = start;
      if (end === start) return 0;
      if (target.length === 0 || this.length === 0) return 0;
      if (targetStart < 0) {
        throw new RangeError("targetStart out of bounds");
      }
      if (start < 0 || start >= this.length) throw new RangeError("Index out of range");
      if (end < 0) throw new RangeError("sourceEnd out of bounds");
      if (end > this.length) end = this.length;
      if (target.length - targetStart < end - start) {
        end = target.length - targetStart + start;
      }
      const len = end - start;
      if (this === target && typeof Uint8Array.prototype.copyWithin === "function") {
        this.copyWithin(targetStart, start, end);
      } else {
        Uint8Array.prototype.set.call(
          target,
          this.subarray(start, end),
          targetStart
        );
      }
      return len;
    };
    Buffer3.prototype.fill = function fill(val, start, end, encoding) {
      if (typeof val === "string") {
        if (typeof start === "string") {
          encoding = start;
          start = 0;
          end = this.length;
        } else if (typeof end === "string") {
          encoding = end;
          end = this.length;
        }
        if (encoding !== void 0 && typeof encoding !== "string") {
          throw new TypeError("encoding must be a string");
        }
        if (typeof encoding === "string" && !Buffer3.isEncoding(encoding)) {
          throw new TypeError("Unknown encoding: " + encoding);
        }
        if (val.length === 1) {
          const code = val.charCodeAt(0);
          if (encoding === "utf8" && code < 128 || encoding === "latin1") {
            val = code;
          }
        }
      } else if (typeof val === "number") {
        val = val & 255;
      } else if (typeof val === "boolean") {
        val = Number(val);
      }
      if (start < 0 || this.length < start || this.length < end) {
        throw new RangeError("Out of range index");
      }
      if (end <= start) {
        return this;
      }
      start = start >>> 0;
      end = end === void 0 ? this.length : end >>> 0;
      if (!val) val = 0;
      let i;
      if (typeof val === "number") {
        for (i = start; i < end; ++i) {
          this[i] = val;
        }
      } else {
        const bytes = Buffer3.isBuffer(val) ? val : Buffer3.from(val, encoding);
        const len = bytes.length;
        if (len === 0) {
          throw new TypeError('The value "' + val + '" is invalid for argument "value"');
        }
        for (i = 0; i < end - start; ++i) {
          this[i + start] = bytes[i % len];
        }
      }
      return this;
    };
    var errors = {};
    function E(sym, getMessage, Base) {
      errors[sym] = class NodeError extends Base {
        constructor() {
          super();
          Object.defineProperty(this, "message", {
            value: getMessage.apply(this, arguments),
            writable: true,
            configurable: true
          });
          this.name = `${this.name} [${sym}]`;
          this.stack;
          delete this.name;
        }
        get code() {
          return sym;
        }
        set code(value) {
          Object.defineProperty(this, "code", {
            configurable: true,
            enumerable: true,
            value,
            writable: true
          });
        }
        toString() {
          return `${this.name} [${sym}]: ${this.message}`;
        }
      };
    }
    E(
      "ERR_BUFFER_OUT_OF_BOUNDS",
      function(name) {
        if (name) {
          return `${name} is outside of buffer bounds`;
        }
        return "Attempt to access memory outside buffer bounds";
      },
      RangeError
    );
    E(
      "ERR_INVALID_ARG_TYPE",
      function(name, actual) {
        return `The "${name}" argument must be of type number. Received type ${typeof actual}`;
      },
      TypeError
    );
    E(
      "ERR_OUT_OF_RANGE",
      function(str, range, input) {
        let msg = `The value of "${str}" is out of range.`;
        let received = input;
        if (Number.isInteger(input) && Math.abs(input) > 2 ** 32) {
          received = addNumericalSeparator(String(input));
        } else if (typeof input === "bigint") {
          received = String(input);
          if (input > BigInt(2) ** BigInt(32) || input < -(BigInt(2) ** BigInt(32))) {
            received = addNumericalSeparator(received);
          }
          received += "n";
        }
        msg += ` It must be ${range}. Received ${received}`;
        return msg;
      },
      RangeError
    );
    function addNumericalSeparator(val) {
      let res = "";
      let i = val.length;
      const start = val[0] === "-" ? 1 : 0;
      for (; i >= start + 4; i -= 3) {
        res = `_${val.slice(i - 3, i)}${res}`;
      }
      return `${val.slice(0, i)}${res}`;
    }
    function checkBounds(buf, offset, byteLength2) {
      validateNumber(offset, "offset");
      if (buf[offset] === void 0 || buf[offset + byteLength2] === void 0) {
        boundsError(offset, buf.length - (byteLength2 + 1));
      }
    }
    function checkIntBI(value, min, max, buf, offset, byteLength2) {
      if (value > max || value < min) {
        const n = typeof min === "bigint" ? "n" : "";
        let range;
        if (byteLength2 > 3) {
          if (min === 0 || min === BigInt(0)) {
            range = `>= 0${n} and < 2${n} ** ${(byteLength2 + 1) * 8}${n}`;
          } else {
            range = `>= -(2${n} ** ${(byteLength2 + 1) * 8 - 1}${n}) and < 2 ** ${(byteLength2 + 1) * 8 - 1}${n}`;
          }
        } else {
          range = `>= ${min}${n} and <= ${max}${n}`;
        }
        throw new errors.ERR_OUT_OF_RANGE("value", range, value);
      }
      checkBounds(buf, offset, byteLength2);
    }
    function validateNumber(value, name) {
      if (typeof value !== "number") {
        throw new errors.ERR_INVALID_ARG_TYPE(name, "number", value);
      }
    }
    function boundsError(value, length, type) {
      if (Math.floor(value) !== value) {
        validateNumber(value, type);
        throw new errors.ERR_OUT_OF_RANGE(type || "offset", "an integer", value);
      }
      if (length < 0) {
        throw new errors.ERR_BUFFER_OUT_OF_BOUNDS();
      }
      throw new errors.ERR_OUT_OF_RANGE(
        type || "offset",
        `>= ${type ? 1 : 0} and <= ${length}`,
        value
      );
    }
    var INVALID_BASE64_RE = /[^+/0-9A-Za-z-_]/g;
    function base64clean(str) {
      str = str.split("=")[0];
      str = str.trim().replace(INVALID_BASE64_RE, "");
      if (str.length < 2) return "";
      while (str.length % 4 !== 0) {
        str = str + "=";
      }
      return str;
    }
    function utf8ToBytes(string, units) {
      units = units || Infinity;
      let codePoint;
      const length = string.length;
      let leadSurrogate = null;
      const bytes = [];
      for (let i = 0; i < length; ++i) {
        codePoint = string.charCodeAt(i);
        if (codePoint > 55295 && codePoint < 57344) {
          if (!leadSurrogate) {
            if (codePoint > 56319) {
              if ((units -= 3) > -1) bytes.push(239, 191, 189);
              continue;
            } else if (i + 1 === length) {
              if ((units -= 3) > -1) bytes.push(239, 191, 189);
              continue;
            }
            leadSurrogate = codePoint;
            continue;
          }
          if (codePoint < 56320) {
            if ((units -= 3) > -1) bytes.push(239, 191, 189);
            leadSurrogate = codePoint;
            continue;
          }
          codePoint = (leadSurrogate - 55296 << 10 | codePoint - 56320) + 65536;
        } else if (leadSurrogate) {
          if ((units -= 3) > -1) bytes.push(239, 191, 189);
        }
        leadSurrogate = null;
        if (codePoint < 128) {
          if ((units -= 1) < 0) break;
          bytes.push(codePoint);
        } else if (codePoint < 2048) {
          if ((units -= 2) < 0) break;
          bytes.push(
            codePoint >> 6 | 192,
            codePoint & 63 | 128
          );
        } else if (codePoint < 65536) {
          if ((units -= 3) < 0) break;
          bytes.push(
            codePoint >> 12 | 224,
            codePoint >> 6 & 63 | 128,
            codePoint & 63 | 128
          );
        } else if (codePoint < 1114112) {
          if ((units -= 4) < 0) break;
          bytes.push(
            codePoint >> 18 | 240,
            codePoint >> 12 & 63 | 128,
            codePoint >> 6 & 63 | 128,
            codePoint & 63 | 128
          );
        } else {
          throw new Error("Invalid code point");
        }
      }
      return bytes;
    }
    function asciiToBytes(str) {
      const byteArray = [];
      for (let i = 0; i < str.length; ++i) {
        byteArray.push(str.charCodeAt(i) & 255);
      }
      return byteArray;
    }
    function utf16leToBytes(str, units) {
      let c, hi, lo;
      const byteArray = [];
      for (let i = 0; i < str.length; ++i) {
        if ((units -= 2) < 0) break;
        c = str.charCodeAt(i);
        hi = c >> 8;
        lo = c % 256;
        byteArray.push(lo);
        byteArray.push(hi);
      }
      return byteArray;
    }
    function base64ToBytes(str) {
      return base64.toByteArray(base64clean(str));
    }
    function blitBuffer(src, dst, offset, length) {
      let i;
      for (i = 0; i < length; ++i) {
        if (i + offset >= dst.length || i >= src.length) break;
        dst[i + offset] = src[i];
      }
      return i;
    }
    function isInstance(obj, type) {
      return obj instanceof type || obj != null && obj.constructor != null && obj.constructor.name != null && obj.constructor.name === type.name;
    }
    function numberIsNaN(obj) {
      return obj !== obj;
    }
    var hexSliceLookupTable = (function() {
      const alphabet = "0123456789abcdef";
      const table = new Array(256);
      for (let i = 0; i < 16; ++i) {
        const i16 = i * 16;
        for (let j = 0; j < 16; ++j) {
          table[i16 + j] = alphabet[i] + alphabet[j];
        }
      }
      return table;
    })();
    function defineBigIntMethod(fn) {
      return typeof BigInt === "undefined" ? BufferBigIntNotDefined : fn;
    }
    function BufferBigIntNotDefined() {
      throw new Error("BigInt not supported");
    }
  }
});

// ../../apps/obsidian-dayisle/main.mjs
var main_exports = {};
__export(main_exports, {
  default: () => DayislePlugin
});
module.exports = __toCommonJS(main_exports);
var import_obsidian = require("obsidian");

// node_modules/flatpickr/dist/esm/types/options.js
var HOOKS = [
  "onChange",
  "onClose",
  "onDayCreate",
  "onDestroy",
  "onKeyDown",
  "onMonthChange",
  "onOpen",
  "onParseConfig",
  "onReady",
  "onValueUpdate",
  "onYearChange",
  "onPreCalendarPosition"
];
var defaults = {
  _disable: [],
  allowInput: false,
  allowInvalidPreload: false,
  altFormat: "F j, Y",
  altInput: false,
  altInputClass: "form-control input",
  animate: typeof window === "object" && window.navigator.userAgent.indexOf("MSIE") === -1,
  ariaDateFormat: "F j, Y",
  autoFillDefaultTime: true,
  clickOpens: true,
  closeOnSelect: true,
  conjunction: ", ",
  dateFormat: "Y-m-d",
  defaultHour: 12,
  defaultMinute: 0,
  defaultSeconds: 0,
  disable: [],
  disableMobile: false,
  enableSeconds: false,
  enableTime: false,
  errorHandler: function(err) {
    return typeof console !== "undefined" && console.warn(err);
  },
  getWeek: function(givenDate) {
    var date = new Date(givenDate.getTime());
    date.setHours(0, 0, 0, 0);
    date.setDate(date.getDate() + 3 - (date.getDay() + 6) % 7);
    var week1 = new Date(date.getFullYear(), 0, 4);
    return 1 + Math.round(((date.getTime() - week1.getTime()) / 864e5 - 3 + (week1.getDay() + 6) % 7) / 7);
  },
  hourIncrement: 1,
  ignoredFocusElements: [],
  inline: false,
  locale: "default",
  minuteIncrement: 5,
  mode: "single",
  monthSelectorType: "dropdown",
  nextArrow: "<svg version='1.1' xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' viewBox='0 0 17 17'><g></g><path d='M13.207 8.472l-7.854 7.854-0.707-0.707 7.146-7.146-7.146-7.148 0.707-0.707 7.854 7.854z' /></svg>",
  noCalendar: false,
  now: /* @__PURE__ */ new Date(),
  onChange: [],
  onClose: [],
  onDayCreate: [],
  onDestroy: [],
  onKeyDown: [],
  onMonthChange: [],
  onOpen: [],
  onParseConfig: [],
  onReady: [],
  onValueUpdate: [],
  onYearChange: [],
  onPreCalendarPosition: [],
  plugins: [],
  position: "auto",
  positionElement: void 0,
  prevArrow: "<svg version='1.1' xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' viewBox='0 0 17 17'><g></g><path d='M5.207 8.471l7.146 7.147-0.707 0.707-7.853-7.854 7.854-7.853 0.707 0.707-7.147 7.146z' /></svg>",
  shorthandCurrentMonth: false,
  showMonths: 1,
  static: false,
  time_24hr: false,
  weekNumbers: false,
  wrap: false
};

// node_modules/flatpickr/dist/esm/l10n/default.js
var english = {
  weekdays: {
    shorthand: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
    longhand: [
      "Sunday",
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday"
    ]
  },
  months: {
    shorthand: [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec"
    ],
    longhand: [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December"
    ]
  },
  daysInMonth: [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31],
  firstDayOfWeek: 0,
  ordinal: function(nth) {
    var s = nth % 100;
    if (s > 3 && s < 21)
      return "th";
    switch (s % 10) {
      case 1:
        return "st";
      case 2:
        return "nd";
      case 3:
        return "rd";
      default:
        return "th";
    }
  },
  rangeSeparator: " to ",
  weekAbbreviation: "Wk",
  scrollTitle: "Scroll to increment",
  toggleTitle: "Click to toggle",
  amPM: ["AM", "PM"],
  yearAriaLabel: "Year",
  monthAriaLabel: "Month",
  hourAriaLabel: "Hour",
  minuteAriaLabel: "Minute",
  time_24hr: false
};
var default_default = english;

// node_modules/flatpickr/dist/esm/utils/index.js
var pad = function(number, length) {
  if (length === void 0) {
    length = 2;
  }
  return ("000" + number).slice(length * -1);
};
var int = function(bool) {
  return bool === true ? 1 : 0;
};
function debounce(fn, wait) {
  var t;
  return function() {
    var _this = this;
    var args = arguments;
    clearTimeout(t);
    t = setTimeout(function() {
      return fn.apply(_this, args);
    }, wait);
  };
}
var arrayify = function(obj) {
  return obj instanceof Array ? obj : [obj];
};

// node_modules/flatpickr/dist/esm/utils/dom.js
function toggleClass(elem, className, bool) {
  if (bool === true)
    return elem.classList.add(className);
  elem.classList.remove(className);
}
function createElement(tag, className, content) {
  var e = window.document.createElement(tag);
  className = className || "";
  content = content || "";
  e.className = className;
  if (content !== void 0)
    e.textContent = content;
  return e;
}
function clearNode(node) {
  while (node.firstChild)
    node.removeChild(node.firstChild);
}
function findParent(node, condition) {
  if (condition(node))
    return node;
  else if (node.parentNode)
    return findParent(node.parentNode, condition);
  return void 0;
}
function createNumberInput(inputClassName, opts) {
  var wrapper = createElement("div", "numInputWrapper"), numInput = createElement("input", "numInput " + inputClassName), arrowUp = createElement("span", "arrowUp"), arrowDown = createElement("span", "arrowDown");
  if (navigator.userAgent.indexOf("MSIE 9.0") === -1) {
    numInput.type = "number";
  } else {
    numInput.type = "text";
    numInput.pattern = "\\d*";
  }
  if (opts !== void 0)
    for (var key2 in opts)
      numInput.setAttribute(key2, opts[key2]);
  wrapper.appendChild(numInput);
  wrapper.appendChild(arrowUp);
  wrapper.appendChild(arrowDown);
  return wrapper;
}
function getEventTarget(event) {
  try {
    if (typeof event.composedPath === "function") {
      var path = event.composedPath();
      return path[0];
    }
    return event.target;
  } catch (error) {
    return event.target;
  }
}

// node_modules/flatpickr/dist/esm/utils/formatting.js
var doNothing = function() {
  return void 0;
};
var monthToStr = function(monthNumber, shorthand, locale) {
  return locale.months[shorthand ? "shorthand" : "longhand"][monthNumber];
};
var revFormat = {
  D: doNothing,
  F: function(dateObj, monthName, locale) {
    dateObj.setMonth(locale.months.longhand.indexOf(monthName));
  },
  G: function(dateObj, hour) {
    dateObj.setHours((dateObj.getHours() >= 12 ? 12 : 0) + parseFloat(hour));
  },
  H: function(dateObj, hour) {
    dateObj.setHours(parseFloat(hour));
  },
  J: function(dateObj, day) {
    dateObj.setDate(parseFloat(day));
  },
  K: function(dateObj, amPM, locale) {
    dateObj.setHours(dateObj.getHours() % 12 + 12 * int(new RegExp(locale.amPM[1], "i").test(amPM)));
  },
  M: function(dateObj, shortMonth, locale) {
    dateObj.setMonth(locale.months.shorthand.indexOf(shortMonth));
  },
  S: function(dateObj, seconds) {
    dateObj.setSeconds(parseFloat(seconds));
  },
  U: function(_, unixSeconds) {
    return new Date(parseFloat(unixSeconds) * 1e3);
  },
  W: function(dateObj, weekNum, locale) {
    var weekNumber = parseInt(weekNum);
    var date = new Date(dateObj.getFullYear(), 0, 2 + (weekNumber - 1) * 7, 0, 0, 0, 0);
    date.setDate(date.getDate() - date.getDay() + locale.firstDayOfWeek);
    return date;
  },
  Y: function(dateObj, year) {
    dateObj.setFullYear(parseFloat(year));
  },
  Z: function(_, ISODate) {
    return new Date(ISODate);
  },
  d: function(dateObj, day) {
    dateObj.setDate(parseFloat(day));
  },
  h: function(dateObj, hour) {
    dateObj.setHours((dateObj.getHours() >= 12 ? 12 : 0) + parseFloat(hour));
  },
  i: function(dateObj, minutes) {
    dateObj.setMinutes(parseFloat(minutes));
  },
  j: function(dateObj, day) {
    dateObj.setDate(parseFloat(day));
  },
  l: doNothing,
  m: function(dateObj, month) {
    dateObj.setMonth(parseFloat(month) - 1);
  },
  n: function(dateObj, month) {
    dateObj.setMonth(parseFloat(month) - 1);
  },
  s: function(dateObj, seconds) {
    dateObj.setSeconds(parseFloat(seconds));
  },
  u: function(_, unixMillSeconds) {
    return new Date(parseFloat(unixMillSeconds));
  },
  w: doNothing,
  y: function(dateObj, year) {
    dateObj.setFullYear(2e3 + parseFloat(year));
  }
};
var tokenRegex = {
  D: "",
  F: "",
  G: "(\\d\\d|\\d)",
  H: "(\\d\\d|\\d)",
  J: "(\\d\\d|\\d)\\w+",
  K: "",
  M: "",
  S: "(\\d\\d|\\d)",
  U: "(.+)",
  W: "(\\d\\d|\\d)",
  Y: "(\\d{4})",
  Z: "(.+)",
  d: "(\\d\\d|\\d)",
  h: "(\\d\\d|\\d)",
  i: "(\\d\\d|\\d)",
  j: "(\\d\\d|\\d)",
  l: "",
  m: "(\\d\\d|\\d)",
  n: "(\\d\\d|\\d)",
  s: "(\\d\\d|\\d)",
  u: "(.+)",
  w: "(\\d\\d|\\d)",
  y: "(\\d{2})"
};
var formats = {
  Z: function(date) {
    return date.toISOString();
  },
  D: function(date, locale, options) {
    return locale.weekdays.shorthand[formats.w(date, locale, options)];
  },
  F: function(date, locale, options) {
    return monthToStr(formats.n(date, locale, options) - 1, false, locale);
  },
  G: function(date, locale, options) {
    return pad(formats.h(date, locale, options));
  },
  H: function(date) {
    return pad(date.getHours());
  },
  J: function(date, locale) {
    return locale.ordinal !== void 0 ? date.getDate() + locale.ordinal(date.getDate()) : date.getDate();
  },
  K: function(date, locale) {
    return locale.amPM[int(date.getHours() > 11)];
  },
  M: function(date, locale) {
    return monthToStr(date.getMonth(), true, locale);
  },
  S: function(date) {
    return pad(date.getSeconds());
  },
  U: function(date) {
    return date.getTime() / 1e3;
  },
  W: function(date, _, options) {
    return options.getWeek(date);
  },
  Y: function(date) {
    return pad(date.getFullYear(), 4);
  },
  d: function(date) {
    return pad(date.getDate());
  },
  h: function(date) {
    return date.getHours() % 12 ? date.getHours() % 12 : 12;
  },
  i: function(date) {
    return pad(date.getMinutes());
  },
  j: function(date) {
    return date.getDate();
  },
  l: function(date, locale) {
    return locale.weekdays.longhand[date.getDay()];
  },
  m: function(date) {
    return pad(date.getMonth() + 1);
  },
  n: function(date) {
    return date.getMonth() + 1;
  },
  s: function(date) {
    return date.getSeconds();
  },
  u: function(date) {
    return date.getTime();
  },
  w: function(date) {
    return date.getDay();
  },
  y: function(date) {
    return String(date.getFullYear()).substring(2);
  }
};

// node_modules/flatpickr/dist/esm/utils/dates.js
var createDateFormatter = function(_a) {
  var _b = _a.config, config = _b === void 0 ? defaults : _b, _c = _a.l10n, l10n = _c === void 0 ? english : _c, _d = _a.isMobile, isMobile = _d === void 0 ? false : _d;
  return function(dateObj, frmt, overrideLocale) {
    var locale = overrideLocale || l10n;
    if (config.formatDate !== void 0 && !isMobile) {
      return config.formatDate(dateObj, frmt, locale);
    }
    return frmt.split("").map(function(c, i, arr) {
      return formats[c] && arr[i - 1] !== "\\" ? formats[c](dateObj, locale, config) : c !== "\\" ? c : "";
    }).join("");
  };
};
var createDateParser = function(_a) {
  var _b = _a.config, config = _b === void 0 ? defaults : _b, _c = _a.l10n, l10n = _c === void 0 ? english : _c;
  return function(date, givenFormat, timeless, customLocale) {
    if (date !== 0 && !date)
      return void 0;
    var locale = customLocale || l10n;
    var parsedDate;
    var dateOrig = date;
    if (date instanceof Date)
      parsedDate = new Date(date.getTime());
    else if (typeof date !== "string" && date.toFixed !== void 0)
      parsedDate = new Date(date);
    else if (typeof date === "string") {
      var format = givenFormat || (config || defaults).dateFormat;
      var datestr = String(date).trim();
      if (datestr === "today") {
        parsedDate = /* @__PURE__ */ new Date();
        timeless = true;
      } else if (config && config.parseDate) {
        parsedDate = config.parseDate(date, format);
      } else if (/Z$/.test(datestr) || /GMT$/.test(datestr)) {
        parsedDate = new Date(date);
      } else {
        var matched = void 0, ops = [];
        for (var i = 0, matchIndex = 0, regexStr = ""; i < format.length; i++) {
          var token = format[i];
          var isBackSlash = token === "\\";
          var escaped = format[i - 1] === "\\" || isBackSlash;
          if (tokenRegex[token] && !escaped) {
            regexStr += tokenRegex[token];
            var match = new RegExp(regexStr).exec(date);
            if (match && (matched = true)) {
              ops[token !== "Y" ? "push" : "unshift"]({
                fn: revFormat[token],
                val: match[++matchIndex]
              });
            }
          } else if (!isBackSlash)
            regexStr += ".";
        }
        parsedDate = !config || !config.noCalendar ? new Date((/* @__PURE__ */ new Date()).getFullYear(), 0, 1, 0, 0, 0, 0) : new Date((/* @__PURE__ */ new Date()).setHours(0, 0, 0, 0));
        ops.forEach(function(_a2) {
          var fn = _a2.fn, val = _a2.val;
          return parsedDate = fn(parsedDate, val, locale) || parsedDate;
        });
        parsedDate = matched ? parsedDate : void 0;
      }
    }
    if (!(parsedDate instanceof Date && !isNaN(parsedDate.getTime()))) {
      config.errorHandler(new Error("Invalid date provided: " + dateOrig));
      return void 0;
    }
    if (timeless === true)
      parsedDate.setHours(0, 0, 0, 0);
    return parsedDate;
  };
};
function compareDates(date1, date2, timeless) {
  if (timeless === void 0) {
    timeless = true;
  }
  if (timeless !== false) {
    return new Date(date1.getTime()).setHours(0, 0, 0, 0) - new Date(date2.getTime()).setHours(0, 0, 0, 0);
  }
  return date1.getTime() - date2.getTime();
}
var isBetween = function(ts, ts1, ts2) {
  return ts > Math.min(ts1, ts2) && ts < Math.max(ts1, ts2);
};
var calculateSecondsSinceMidnight = function(hours, minutes, seconds) {
  return hours * 3600 + minutes * 60 + seconds;
};
var parseSeconds = function(secondsSinceMidnight) {
  var hours = Math.floor(secondsSinceMidnight / 3600), minutes = (secondsSinceMidnight - hours * 3600) / 60;
  return [hours, minutes, secondsSinceMidnight - hours * 3600 - minutes * 60];
};
var duration = {
  DAY: 864e5
};
function getDefaultHours(config) {
  var hours = config.defaultHour;
  var minutes = config.defaultMinute;
  var seconds = config.defaultSeconds;
  if (config.minDate !== void 0) {
    var minHour = config.minDate.getHours();
    var minMinutes = config.minDate.getMinutes();
    var minSeconds = config.minDate.getSeconds();
    if (hours < minHour) {
      hours = minHour;
    }
    if (hours === minHour && minutes < minMinutes) {
      minutes = minMinutes;
    }
    if (hours === minHour && minutes === minMinutes && seconds < minSeconds)
      seconds = config.minDate.getSeconds();
  }
  if (config.maxDate !== void 0) {
    var maxHr = config.maxDate.getHours();
    var maxMinutes = config.maxDate.getMinutes();
    hours = Math.min(hours, maxHr);
    if (hours === maxHr)
      minutes = Math.min(maxMinutes, minutes);
    if (hours === maxHr && minutes === maxMinutes)
      seconds = config.maxDate.getSeconds();
  }
  return { hours, minutes, seconds };
}

// node_modules/flatpickr/dist/esm/utils/polyfills.js
if (typeof Object.assign !== "function") {
  Object.assign = function(target) {
    var args = [];
    for (var _i = 1; _i < arguments.length; _i++) {
      args[_i - 1] = arguments[_i];
    }
    if (!target) {
      throw TypeError("Cannot convert undefined or null to object");
    }
    var _loop_1 = function(source2) {
      if (source2) {
        Object.keys(source2).forEach(function(key2) {
          return target[key2] = source2[key2];
        });
      }
    };
    for (var _a = 0, args_1 = args; _a < args_1.length; _a++) {
      var source = args_1[_a];
      _loop_1(source);
    }
    return target;
  };
}

// node_modules/flatpickr/dist/esm/index.js
var __assign = function() {
  __assign = Object.assign || function(t) {
    for (var s, i = 1, n = arguments.length; i < n; i++) {
      s = arguments[i];
      for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p))
        t[p] = s[p];
    }
    return t;
  };
  return __assign.apply(this, arguments);
};
var __spreadArrays = function() {
  for (var s = 0, i = 0, il = arguments.length; i < il; i++) s += arguments[i].length;
  for (var r = Array(s), k = 0, i = 0; i < il; i++)
    for (var a = arguments[i], j = 0, jl = a.length; j < jl; j++, k++)
      r[k] = a[j];
  return r;
};
var DEBOUNCED_CHANGE_MS = 300;
function FlatpickrInstance(element, instanceConfig) {
  var self2 = {
    config: __assign(__assign({}, defaults), flatpickr.defaultConfig),
    l10n: default_default
  };
  self2.parseDate = createDateParser({ config: self2.config, l10n: self2.l10n });
  self2._handlers = [];
  self2.pluginElements = [];
  self2.loadedPlugins = [];
  self2._bind = bind;
  self2._setHoursFromDate = setHoursFromDate;
  self2._positionCalendar = positionCalendar;
  self2.changeMonth = changeMonth;
  self2.changeYear = changeYear;
  self2.clear = clear;
  self2.close = close;
  self2.onMouseOver = onMouseOver;
  self2._createElement = createElement;
  self2.createDay = createDay;
  self2.destroy = destroy;
  self2.isEnabled = isEnabled;
  self2.jumpToDate = jumpToDate;
  self2.updateValue = updateValue;
  self2.open = open;
  self2.redraw = redraw;
  self2.set = set;
  self2.setDate = setDate;
  self2.toggle = toggle;
  function setupHelperFunctions() {
    self2.utils = {
      getDaysInMonth: function(month, yr) {
        if (month === void 0) {
          month = self2.currentMonth;
        }
        if (yr === void 0) {
          yr = self2.currentYear;
        }
        if (month === 1 && (yr % 4 === 0 && yr % 100 !== 0 || yr % 400 === 0))
          return 29;
        return self2.l10n.daysInMonth[month];
      }
    };
  }
  function init() {
    self2.element = self2.input = element;
    self2.isOpen = false;
    parseConfig();
    setupLocale();
    setupInputs();
    setupDates();
    setupHelperFunctions();
    if (!self2.isMobile)
      build();
    bindEvents();
    if (self2.selectedDates.length || self2.config.noCalendar) {
      if (self2.config.enableTime) {
        setHoursFromDate(self2.config.noCalendar ? self2.latestSelectedDateObj : void 0);
      }
      updateValue(false);
    }
    setCalendarWidth();
    var isSafari = /^((?!chrome|android).)*safari/i.test(navigator.userAgent);
    if (!self2.isMobile && isSafari) {
      positionCalendar();
    }
    triggerEvent("onReady");
  }
  function getClosestActiveElement() {
    var _a;
    return ((_a = self2.calendarContainer) === null || _a === void 0 ? void 0 : _a.getRootNode()).activeElement || document.activeElement;
  }
  function bindToInstance(fn) {
    return fn.bind(self2);
  }
  function setCalendarWidth() {
    var config = self2.config;
    if (config.weekNumbers === false && config.showMonths === 1) {
      return;
    } else if (config.noCalendar !== true) {
      window.requestAnimationFrame(function() {
        if (self2.calendarContainer !== void 0) {
          self2.calendarContainer.style.visibility = "hidden";
          self2.calendarContainer.style.display = "block";
        }
        if (self2.daysContainer !== void 0) {
          var daysWidth = (self2.days.offsetWidth + 1) * config.showMonths;
          self2.daysContainer.style.width = daysWidth + "px";
          self2.calendarContainer.style.width = daysWidth + (self2.weekWrapper !== void 0 ? self2.weekWrapper.offsetWidth : 0) + "px";
          self2.calendarContainer.style.removeProperty("visibility");
          self2.calendarContainer.style.removeProperty("display");
        }
      });
    }
  }
  function updateTime(e) {
    if (self2.selectedDates.length === 0) {
      var defaultDate = self2.config.minDate === void 0 || compareDates(/* @__PURE__ */ new Date(), self2.config.minDate) >= 0 ? /* @__PURE__ */ new Date() : new Date(self2.config.minDate.getTime());
      var defaults2 = getDefaultHours(self2.config);
      defaultDate.setHours(defaults2.hours, defaults2.minutes, defaults2.seconds, defaultDate.getMilliseconds());
      self2.selectedDates = [defaultDate];
      self2.latestSelectedDateObj = defaultDate;
    }
    if (e !== void 0 && e.type !== "blur") {
      timeWrapper(e);
    }
    var prevValue = self2._input.value;
    setHoursFromInputs();
    updateValue();
    if (self2._input.value !== prevValue) {
      self2._debouncedChange();
    }
  }
  function ampm2military(hour, amPM) {
    return hour % 12 + 12 * int(amPM === self2.l10n.amPM[1]);
  }
  function military2ampm(hour) {
    switch (hour % 24) {
      case 0:
      case 12:
        return 12;
      default:
        return hour % 12;
    }
  }
  function setHoursFromInputs() {
    if (self2.hourElement === void 0 || self2.minuteElement === void 0)
      return;
    var hours = (parseInt(self2.hourElement.value.slice(-2), 10) || 0) % 24, minutes = (parseInt(self2.minuteElement.value, 10) || 0) % 60, seconds = self2.secondElement !== void 0 ? (parseInt(self2.secondElement.value, 10) || 0) % 60 : 0;
    if (self2.amPM !== void 0) {
      hours = ampm2military(hours, self2.amPM.textContent);
    }
    var limitMinHours = self2.config.minTime !== void 0 || self2.config.minDate && self2.minDateHasTime && self2.latestSelectedDateObj && compareDates(self2.latestSelectedDateObj, self2.config.minDate, true) === 0;
    var limitMaxHours = self2.config.maxTime !== void 0 || self2.config.maxDate && self2.maxDateHasTime && self2.latestSelectedDateObj && compareDates(self2.latestSelectedDateObj, self2.config.maxDate, true) === 0;
    if (self2.config.maxTime !== void 0 && self2.config.minTime !== void 0 && self2.config.minTime > self2.config.maxTime) {
      var minBound = calculateSecondsSinceMidnight(self2.config.minTime.getHours(), self2.config.minTime.getMinutes(), self2.config.minTime.getSeconds());
      var maxBound = calculateSecondsSinceMidnight(self2.config.maxTime.getHours(), self2.config.maxTime.getMinutes(), self2.config.maxTime.getSeconds());
      var currentTime = calculateSecondsSinceMidnight(hours, minutes, seconds);
      if (currentTime > maxBound && currentTime < minBound) {
        var result = parseSeconds(minBound);
        hours = result[0];
        minutes = result[1];
        seconds = result[2];
      }
    } else {
      if (limitMaxHours) {
        var maxTime = self2.config.maxTime !== void 0 ? self2.config.maxTime : self2.config.maxDate;
        hours = Math.min(hours, maxTime.getHours());
        if (hours === maxTime.getHours())
          minutes = Math.min(minutes, maxTime.getMinutes());
        if (minutes === maxTime.getMinutes())
          seconds = Math.min(seconds, maxTime.getSeconds());
      }
      if (limitMinHours) {
        var minTime = self2.config.minTime !== void 0 ? self2.config.minTime : self2.config.minDate;
        hours = Math.max(hours, minTime.getHours());
        if (hours === minTime.getHours() && minutes < minTime.getMinutes())
          minutes = minTime.getMinutes();
        if (minutes === minTime.getMinutes())
          seconds = Math.max(seconds, minTime.getSeconds());
      }
    }
    setHours(hours, minutes, seconds);
  }
  function setHoursFromDate(dateObj) {
    var date = dateObj || self2.latestSelectedDateObj;
    if (date && date instanceof Date) {
      setHours(date.getHours(), date.getMinutes(), date.getSeconds());
    }
  }
  function setHours(hours, minutes, seconds) {
    if (self2.latestSelectedDateObj !== void 0) {
      self2.latestSelectedDateObj.setHours(hours % 24, minutes, seconds || 0, 0);
    }
    if (!self2.hourElement || !self2.minuteElement || self2.isMobile)
      return;
    self2.hourElement.value = pad(!self2.config.time_24hr ? (12 + hours) % 12 + 12 * int(hours % 12 === 0) : hours);
    self2.minuteElement.value = pad(minutes);
    if (self2.amPM !== void 0)
      self2.amPM.textContent = self2.l10n.amPM[int(hours >= 12)];
    if (self2.secondElement !== void 0)
      self2.secondElement.value = pad(seconds);
  }
  function onYearInput(event) {
    var eventTarget = getEventTarget(event);
    var year = parseInt(eventTarget.value) + (event.delta || 0);
    if (year / 1e3 > 1 || event.key === "Enter" && !/[^\d]/.test(year.toString())) {
      changeYear(year);
    }
  }
  function bind(element2, event, handler, options) {
    if (event instanceof Array)
      return event.forEach(function(ev) {
        return bind(element2, ev, handler, options);
      });
    if (element2 instanceof Array)
      return element2.forEach(function(el) {
        return bind(el, event, handler, options);
      });
    element2.addEventListener(event, handler, options);
    self2._handlers.push({
      remove: function() {
        return element2.removeEventListener(event, handler, options);
      }
    });
  }
  function triggerChange() {
    triggerEvent("onChange");
  }
  function bindEvents() {
    if (self2.config.wrap) {
      ["open", "close", "toggle", "clear"].forEach(function(evt) {
        Array.prototype.forEach.call(self2.element.querySelectorAll("[data-" + evt + "]"), function(el) {
          return bind(el, "click", self2[evt]);
        });
      });
    }
    if (self2.isMobile) {
      setupMobile();
      return;
    }
    var debouncedResize = debounce(onResize, 50);
    self2._debouncedChange = debounce(triggerChange, DEBOUNCED_CHANGE_MS);
    if (self2.daysContainer && !/iPhone|iPad|iPod/i.test(navigator.userAgent))
      bind(self2.daysContainer, "mouseover", function(e) {
        if (self2.config.mode === "range")
          onMouseOver(getEventTarget(e));
      });
    bind(self2._input, "keydown", onKeyDown);
    if (self2.calendarContainer !== void 0) {
      bind(self2.calendarContainer, "keydown", onKeyDown);
    }
    if (!self2.config.inline && !self2.config.static)
      bind(window, "resize", debouncedResize);
    if (window.ontouchstart !== void 0)
      bind(window.document, "touchstart", documentClick);
    else
      bind(window.document, "mousedown", documentClick);
    bind(window.document, "focus", documentClick, { capture: true });
    if (self2.config.clickOpens === true) {
      bind(self2._input, "focus", self2.open);
      bind(self2._input, "click", self2.open);
    }
    if (self2.daysContainer !== void 0) {
      bind(self2.monthNav, "click", onMonthNavClick);
      bind(self2.monthNav, ["keyup", "increment"], onYearInput);
      bind(self2.daysContainer, "click", selectDate);
    }
    if (self2.timeContainer !== void 0 && self2.minuteElement !== void 0 && self2.hourElement !== void 0) {
      var selText = function(e) {
        return getEventTarget(e).select();
      };
      bind(self2.timeContainer, ["increment"], updateTime);
      bind(self2.timeContainer, "blur", updateTime, { capture: true });
      bind(self2.timeContainer, "click", timeIncrement);
      bind([self2.hourElement, self2.minuteElement], ["focus", "click"], selText);
      if (self2.secondElement !== void 0)
        bind(self2.secondElement, "focus", function() {
          return self2.secondElement && self2.secondElement.select();
        });
      if (self2.amPM !== void 0) {
        bind(self2.amPM, "click", function(e) {
          updateTime(e);
        });
      }
    }
    if (self2.config.allowInput) {
      bind(self2._input, "blur", onBlur);
    }
  }
  function jumpToDate(jumpDate, triggerChange2) {
    var jumpTo = jumpDate !== void 0 ? self2.parseDate(jumpDate) : self2.latestSelectedDateObj || (self2.config.minDate && self2.config.minDate > self2.now ? self2.config.minDate : self2.config.maxDate && self2.config.maxDate < self2.now ? self2.config.maxDate : self2.now);
    var oldYear = self2.currentYear;
    var oldMonth = self2.currentMonth;
    try {
      if (jumpTo !== void 0) {
        self2.currentYear = jumpTo.getFullYear();
        self2.currentMonth = jumpTo.getMonth();
      }
    } catch (e) {
      e.message = "Invalid date supplied: " + jumpTo;
      self2.config.errorHandler(e);
    }
    if (triggerChange2 && self2.currentYear !== oldYear) {
      triggerEvent("onYearChange");
      buildMonthSwitch();
    }
    if (triggerChange2 && (self2.currentYear !== oldYear || self2.currentMonth !== oldMonth)) {
      triggerEvent("onMonthChange");
    }
    self2.redraw();
  }
  function timeIncrement(e) {
    var eventTarget = getEventTarget(e);
    if (~eventTarget.className.indexOf("arrow"))
      incrementNumInput(e, eventTarget.classList.contains("arrowUp") ? 1 : -1);
  }
  function incrementNumInput(e, delta, inputElem) {
    var target = e && getEventTarget(e);
    var input = inputElem || target && target.parentNode && target.parentNode.firstChild;
    var event = createEvent("increment");
    event.delta = delta;
    input && input.dispatchEvent(event);
  }
  function build() {
    var fragment = window.document.createDocumentFragment();
    self2.calendarContainer = createElement("div", "flatpickr-calendar");
    self2.calendarContainer.tabIndex = -1;
    if (!self2.config.noCalendar) {
      fragment.appendChild(buildMonthNav());
      self2.innerContainer = createElement("div", "flatpickr-innerContainer");
      if (self2.config.weekNumbers) {
        var _a = buildWeeks(), weekWrapper = _a.weekWrapper, weekNumbers = _a.weekNumbers;
        self2.innerContainer.appendChild(weekWrapper);
        self2.weekNumbers = weekNumbers;
        self2.weekWrapper = weekWrapper;
      }
      self2.rContainer = createElement("div", "flatpickr-rContainer");
      self2.rContainer.appendChild(buildWeekdays());
      if (!self2.daysContainer) {
        self2.daysContainer = createElement("div", "flatpickr-days");
        self2.daysContainer.tabIndex = -1;
      }
      buildDays();
      self2.rContainer.appendChild(self2.daysContainer);
      self2.innerContainer.appendChild(self2.rContainer);
      fragment.appendChild(self2.innerContainer);
    }
    if (self2.config.enableTime) {
      fragment.appendChild(buildTime());
    }
    toggleClass(self2.calendarContainer, "rangeMode", self2.config.mode === "range");
    toggleClass(self2.calendarContainer, "animate", self2.config.animate === true);
    toggleClass(self2.calendarContainer, "multiMonth", self2.config.showMonths > 1);
    self2.calendarContainer.appendChild(fragment);
    var customAppend = self2.config.appendTo !== void 0 && self2.config.appendTo.nodeType !== void 0;
    if (self2.config.inline || self2.config.static) {
      self2.calendarContainer.classList.add(self2.config.inline ? "inline" : "static");
      if (self2.config.inline) {
        if (!customAppend && self2.element.parentNode)
          self2.element.parentNode.insertBefore(self2.calendarContainer, self2._input.nextSibling);
        else if (self2.config.appendTo !== void 0)
          self2.config.appendTo.appendChild(self2.calendarContainer);
      }
      if (self2.config.static) {
        var wrapper = createElement("div", "flatpickr-wrapper");
        if (self2.element.parentNode)
          self2.element.parentNode.insertBefore(wrapper, self2.element);
        wrapper.appendChild(self2.element);
        if (self2.altInput)
          wrapper.appendChild(self2.altInput);
        wrapper.appendChild(self2.calendarContainer);
      }
    }
    if (!self2.config.static && !self2.config.inline)
      (self2.config.appendTo !== void 0 ? self2.config.appendTo : window.document.body).appendChild(self2.calendarContainer);
  }
  function createDay(className, date, _dayNumber, i) {
    var dateIsEnabled = isEnabled(date, true), dayElement = createElement("span", className, date.getDate().toString());
    dayElement.dateObj = date;
    dayElement.$i = i;
    dayElement.setAttribute("aria-label", self2.formatDate(date, self2.config.ariaDateFormat));
    if (className.indexOf("hidden") === -1 && compareDates(date, self2.now) === 0) {
      self2.todayDateElem = dayElement;
      dayElement.classList.add("today");
      dayElement.setAttribute("aria-current", "date");
    }
    if (dateIsEnabled) {
      dayElement.tabIndex = -1;
      if (isDateSelected(date)) {
        dayElement.classList.add("selected");
        self2.selectedDateElem = dayElement;
        if (self2.config.mode === "range") {
          toggleClass(dayElement, "startRange", self2.selectedDates[0] && compareDates(date, self2.selectedDates[0], true) === 0);
          toggleClass(dayElement, "endRange", self2.selectedDates[1] && compareDates(date, self2.selectedDates[1], true) === 0);
          if (className === "nextMonthDay")
            dayElement.classList.add("inRange");
        }
      }
    } else {
      dayElement.classList.add("flatpickr-disabled");
    }
    if (self2.config.mode === "range") {
      if (isDateInRange(date) && !isDateSelected(date))
        dayElement.classList.add("inRange");
    }
    if (self2.weekNumbers && self2.config.showMonths === 1 && className !== "prevMonthDay" && i % 7 === 6) {
      self2.weekNumbers.insertAdjacentHTML("beforeend", "<span class='flatpickr-day'>" + self2.config.getWeek(date) + "</span>");
    }
    triggerEvent("onDayCreate", dayElement);
    return dayElement;
  }
  function focusOnDayElem(targetNode) {
    targetNode.focus();
    if (self2.config.mode === "range")
      onMouseOver(targetNode);
  }
  function getFirstAvailableDay(delta) {
    var startMonth = delta > 0 ? 0 : self2.config.showMonths - 1;
    var endMonth = delta > 0 ? self2.config.showMonths : -1;
    for (var m = startMonth; m != endMonth; m += delta) {
      var month = self2.daysContainer.children[m];
      var startIndex = delta > 0 ? 0 : month.children.length - 1;
      var endIndex = delta > 0 ? month.children.length : -1;
      for (var i = startIndex; i != endIndex; i += delta) {
        var c = month.children[i];
        if (c.className.indexOf("hidden") === -1 && isEnabled(c.dateObj))
          return c;
      }
    }
    return void 0;
  }
  function getNextAvailableDay(current, delta) {
    var givenMonth = current.className.indexOf("Month") === -1 ? current.dateObj.getMonth() : self2.currentMonth;
    var endMonth = delta > 0 ? self2.config.showMonths : -1;
    var loopDelta = delta > 0 ? 1 : -1;
    for (var m = givenMonth - self2.currentMonth; m != endMonth; m += loopDelta) {
      var month = self2.daysContainer.children[m];
      var startIndex = givenMonth - self2.currentMonth === m ? current.$i + delta : delta < 0 ? month.children.length - 1 : 0;
      var numMonthDays = month.children.length;
      for (var i = startIndex; i >= 0 && i < numMonthDays && i != (delta > 0 ? numMonthDays : -1); i += loopDelta) {
        var c = month.children[i];
        if (c.className.indexOf("hidden") === -1 && isEnabled(c.dateObj) && Math.abs(current.$i - i) >= Math.abs(delta))
          return focusOnDayElem(c);
      }
    }
    self2.changeMonth(loopDelta);
    focusOnDay(getFirstAvailableDay(loopDelta), 0);
    return void 0;
  }
  function focusOnDay(current, offset) {
    var activeElement = getClosestActiveElement();
    var dayFocused = isInView(activeElement || document.body);
    var startElem = current !== void 0 ? current : dayFocused ? activeElement : self2.selectedDateElem !== void 0 && isInView(self2.selectedDateElem) ? self2.selectedDateElem : self2.todayDateElem !== void 0 && isInView(self2.todayDateElem) ? self2.todayDateElem : getFirstAvailableDay(offset > 0 ? 1 : -1);
    if (startElem === void 0) {
      self2._input.focus();
    } else if (!dayFocused) {
      focusOnDayElem(startElem);
    } else {
      getNextAvailableDay(startElem, offset);
    }
  }
  function buildMonthDays(year, month) {
    var firstOfMonth = (new Date(year, month, 1).getDay() - self2.l10n.firstDayOfWeek + 7) % 7;
    var prevMonthDays = self2.utils.getDaysInMonth((month - 1 + 12) % 12, year);
    var daysInMonth = self2.utils.getDaysInMonth(month, year), days = window.document.createDocumentFragment(), isMultiMonth = self2.config.showMonths > 1, prevMonthDayClass = isMultiMonth ? "prevMonthDay hidden" : "prevMonthDay", nextMonthDayClass = isMultiMonth ? "nextMonthDay hidden" : "nextMonthDay";
    var dayNumber = prevMonthDays + 1 - firstOfMonth, dayIndex = 0;
    for (; dayNumber <= prevMonthDays; dayNumber++, dayIndex++) {
      days.appendChild(createDay("flatpickr-day " + prevMonthDayClass, new Date(year, month - 1, dayNumber), dayNumber, dayIndex));
    }
    for (dayNumber = 1; dayNumber <= daysInMonth; dayNumber++, dayIndex++) {
      days.appendChild(createDay("flatpickr-day", new Date(year, month, dayNumber), dayNumber, dayIndex));
    }
    for (var dayNum = daysInMonth + 1; dayNum <= 42 - firstOfMonth && (self2.config.showMonths === 1 || dayIndex % 7 !== 0); dayNum++, dayIndex++) {
      days.appendChild(createDay("flatpickr-day " + nextMonthDayClass, new Date(year, month + 1, dayNum % daysInMonth), dayNum, dayIndex));
    }
    var dayContainer = createElement("div", "dayContainer");
    dayContainer.appendChild(days);
    return dayContainer;
  }
  function buildDays() {
    if (self2.daysContainer === void 0) {
      return;
    }
    clearNode(self2.daysContainer);
    if (self2.weekNumbers)
      clearNode(self2.weekNumbers);
    var frag = document.createDocumentFragment();
    for (var i = 0; i < self2.config.showMonths; i++) {
      var d = new Date(self2.currentYear, self2.currentMonth, 1);
      d.setMonth(self2.currentMonth + i);
      frag.appendChild(buildMonthDays(d.getFullYear(), d.getMonth()));
    }
    self2.daysContainer.appendChild(frag);
    self2.days = self2.daysContainer.firstChild;
    if (self2.config.mode === "range" && self2.selectedDates.length === 1) {
      onMouseOver();
    }
  }
  function buildMonthSwitch() {
    if (self2.config.showMonths > 1 || self2.config.monthSelectorType !== "dropdown")
      return;
    var shouldBuildMonth = function(month2) {
      if (self2.config.minDate !== void 0 && self2.currentYear === self2.config.minDate.getFullYear() && month2 < self2.config.minDate.getMonth()) {
        return false;
      }
      return !(self2.config.maxDate !== void 0 && self2.currentYear === self2.config.maxDate.getFullYear() && month2 > self2.config.maxDate.getMonth());
    };
    self2.monthsDropdownContainer.tabIndex = -1;
    self2.monthsDropdownContainer.innerHTML = "";
    for (var i = 0; i < 12; i++) {
      if (!shouldBuildMonth(i))
        continue;
      var month = createElement("option", "flatpickr-monthDropdown-month");
      month.value = new Date(self2.currentYear, i).getMonth().toString();
      month.textContent = monthToStr(i, self2.config.shorthandCurrentMonth, self2.l10n);
      month.tabIndex = -1;
      if (self2.currentMonth === i) {
        month.selected = true;
      }
      self2.monthsDropdownContainer.appendChild(month);
    }
  }
  function buildMonth() {
    var container = createElement("div", "flatpickr-month");
    var monthNavFragment = window.document.createDocumentFragment();
    var monthElement;
    if (self2.config.showMonths > 1 || self2.config.monthSelectorType === "static") {
      monthElement = createElement("span", "cur-month");
    } else {
      self2.monthsDropdownContainer = createElement("select", "flatpickr-monthDropdown-months");
      self2.monthsDropdownContainer.setAttribute("aria-label", self2.l10n.monthAriaLabel);
      bind(self2.monthsDropdownContainer, "change", function(e) {
        var target = getEventTarget(e);
        var selectedMonth = parseInt(target.value, 10);
        self2.changeMonth(selectedMonth - self2.currentMonth);
        triggerEvent("onMonthChange");
      });
      buildMonthSwitch();
      monthElement = self2.monthsDropdownContainer;
    }
    var yearInput = createNumberInput("cur-year", { tabindex: "-1" });
    var yearElement = yearInput.getElementsByTagName("input")[0];
    yearElement.setAttribute("aria-label", self2.l10n.yearAriaLabel);
    if (self2.config.minDate) {
      yearElement.setAttribute("min", self2.config.minDate.getFullYear().toString());
    }
    if (self2.config.maxDate) {
      yearElement.setAttribute("max", self2.config.maxDate.getFullYear().toString());
      yearElement.disabled = !!self2.config.minDate && self2.config.minDate.getFullYear() === self2.config.maxDate.getFullYear();
    }
    var currentMonth = createElement("div", "flatpickr-current-month");
    currentMonth.appendChild(monthElement);
    currentMonth.appendChild(yearInput);
    monthNavFragment.appendChild(currentMonth);
    container.appendChild(monthNavFragment);
    return {
      container,
      yearElement,
      monthElement
    };
  }
  function buildMonths() {
    clearNode(self2.monthNav);
    self2.monthNav.appendChild(self2.prevMonthNav);
    if (self2.config.showMonths) {
      self2.yearElements = [];
      self2.monthElements = [];
    }
    for (var m = self2.config.showMonths; m--; ) {
      var month = buildMonth();
      self2.yearElements.push(month.yearElement);
      self2.monthElements.push(month.monthElement);
      self2.monthNav.appendChild(month.container);
    }
    self2.monthNav.appendChild(self2.nextMonthNav);
  }
  function buildMonthNav() {
    self2.monthNav = createElement("div", "flatpickr-months");
    self2.yearElements = [];
    self2.monthElements = [];
    self2.prevMonthNav = createElement("span", "flatpickr-prev-month");
    self2.prevMonthNav.innerHTML = self2.config.prevArrow;
    self2.nextMonthNav = createElement("span", "flatpickr-next-month");
    self2.nextMonthNav.innerHTML = self2.config.nextArrow;
    buildMonths();
    Object.defineProperty(self2, "_hidePrevMonthArrow", {
      get: function() {
        return self2.__hidePrevMonthArrow;
      },
      set: function(bool) {
        if (self2.__hidePrevMonthArrow !== bool) {
          toggleClass(self2.prevMonthNav, "flatpickr-disabled", bool);
          self2.__hidePrevMonthArrow = bool;
        }
      }
    });
    Object.defineProperty(self2, "_hideNextMonthArrow", {
      get: function() {
        return self2.__hideNextMonthArrow;
      },
      set: function(bool) {
        if (self2.__hideNextMonthArrow !== bool) {
          toggleClass(self2.nextMonthNav, "flatpickr-disabled", bool);
          self2.__hideNextMonthArrow = bool;
        }
      }
    });
    self2.currentYearElement = self2.yearElements[0];
    updateNavigationCurrentMonth();
    return self2.monthNav;
  }
  function buildTime() {
    self2.calendarContainer.classList.add("hasTime");
    if (self2.config.noCalendar)
      self2.calendarContainer.classList.add("noCalendar");
    var defaults2 = getDefaultHours(self2.config);
    self2.timeContainer = createElement("div", "flatpickr-time");
    self2.timeContainer.tabIndex = -1;
    var separator = createElement("span", "flatpickr-time-separator", ":");
    var hourInput = createNumberInput("flatpickr-hour", {
      "aria-label": self2.l10n.hourAriaLabel
    });
    self2.hourElement = hourInput.getElementsByTagName("input")[0];
    var minuteInput = createNumberInput("flatpickr-minute", {
      "aria-label": self2.l10n.minuteAriaLabel
    });
    self2.minuteElement = minuteInput.getElementsByTagName("input")[0];
    self2.hourElement.tabIndex = self2.minuteElement.tabIndex = -1;
    self2.hourElement.value = pad(self2.latestSelectedDateObj ? self2.latestSelectedDateObj.getHours() : self2.config.time_24hr ? defaults2.hours : military2ampm(defaults2.hours));
    self2.minuteElement.value = pad(self2.latestSelectedDateObj ? self2.latestSelectedDateObj.getMinutes() : defaults2.minutes);
    self2.hourElement.setAttribute("step", self2.config.hourIncrement.toString());
    self2.minuteElement.setAttribute("step", self2.config.minuteIncrement.toString());
    self2.hourElement.setAttribute("min", self2.config.time_24hr ? "0" : "1");
    self2.hourElement.setAttribute("max", self2.config.time_24hr ? "23" : "12");
    self2.hourElement.setAttribute("maxlength", "2");
    self2.minuteElement.setAttribute("min", "0");
    self2.minuteElement.setAttribute("max", "59");
    self2.minuteElement.setAttribute("maxlength", "2");
    self2.timeContainer.appendChild(hourInput);
    self2.timeContainer.appendChild(separator);
    self2.timeContainer.appendChild(minuteInput);
    if (self2.config.time_24hr)
      self2.timeContainer.classList.add("time24hr");
    if (self2.config.enableSeconds) {
      self2.timeContainer.classList.add("hasSeconds");
      var secondInput = createNumberInput("flatpickr-second");
      self2.secondElement = secondInput.getElementsByTagName("input")[0];
      self2.secondElement.value = pad(self2.latestSelectedDateObj ? self2.latestSelectedDateObj.getSeconds() : defaults2.seconds);
      self2.secondElement.setAttribute("step", self2.minuteElement.getAttribute("step"));
      self2.secondElement.setAttribute("min", "0");
      self2.secondElement.setAttribute("max", "59");
      self2.secondElement.setAttribute("maxlength", "2");
      self2.timeContainer.appendChild(createElement("span", "flatpickr-time-separator", ":"));
      self2.timeContainer.appendChild(secondInput);
    }
    if (!self2.config.time_24hr) {
      self2.amPM = createElement("span", "flatpickr-am-pm", self2.l10n.amPM[int((self2.latestSelectedDateObj ? self2.hourElement.value : self2.config.defaultHour) > 11)]);
      self2.amPM.title = self2.l10n.toggleTitle;
      self2.amPM.tabIndex = -1;
      self2.timeContainer.appendChild(self2.amPM);
    }
    return self2.timeContainer;
  }
  function buildWeekdays() {
    if (!self2.weekdayContainer)
      self2.weekdayContainer = createElement("div", "flatpickr-weekdays");
    else
      clearNode(self2.weekdayContainer);
    for (var i = self2.config.showMonths; i--; ) {
      var container = createElement("div", "flatpickr-weekdaycontainer");
      self2.weekdayContainer.appendChild(container);
    }
    updateWeekdays();
    return self2.weekdayContainer;
  }
  function updateWeekdays() {
    if (!self2.weekdayContainer) {
      return;
    }
    var firstDayOfWeek = self2.l10n.firstDayOfWeek;
    var weekdays = __spreadArrays(self2.l10n.weekdays.shorthand);
    if (firstDayOfWeek > 0 && firstDayOfWeek < weekdays.length) {
      weekdays = __spreadArrays(weekdays.splice(firstDayOfWeek, weekdays.length), weekdays.splice(0, firstDayOfWeek));
    }
    for (var i = self2.config.showMonths; i--; ) {
      self2.weekdayContainer.children[i].innerHTML = "\n      <span class='flatpickr-weekday'>\n        " + weekdays.join("</span><span class='flatpickr-weekday'>") + "\n      </span>\n      ";
    }
  }
  function buildWeeks() {
    self2.calendarContainer.classList.add("hasWeeks");
    var weekWrapper = createElement("div", "flatpickr-weekwrapper");
    weekWrapper.appendChild(createElement("span", "flatpickr-weekday", self2.l10n.weekAbbreviation));
    var weekNumbers = createElement("div", "flatpickr-weeks");
    weekWrapper.appendChild(weekNumbers);
    return {
      weekWrapper,
      weekNumbers
    };
  }
  function changeMonth(value, isOffset) {
    if (isOffset === void 0) {
      isOffset = true;
    }
    var delta = isOffset ? value : value - self2.currentMonth;
    if (delta < 0 && self2._hidePrevMonthArrow === true || delta > 0 && self2._hideNextMonthArrow === true)
      return;
    self2.currentMonth += delta;
    if (self2.currentMonth < 0 || self2.currentMonth > 11) {
      self2.currentYear += self2.currentMonth > 11 ? 1 : -1;
      self2.currentMonth = (self2.currentMonth + 12) % 12;
      triggerEvent("onYearChange");
      buildMonthSwitch();
    }
    buildDays();
    triggerEvent("onMonthChange");
    updateNavigationCurrentMonth();
  }
  function clear(triggerChangeEvent, toInitial) {
    if (triggerChangeEvent === void 0) {
      triggerChangeEvent = true;
    }
    if (toInitial === void 0) {
      toInitial = true;
    }
    self2.input.value = "";
    if (self2.altInput !== void 0)
      self2.altInput.value = "";
    if (self2.mobileInput !== void 0)
      self2.mobileInput.value = "";
    self2.selectedDates = [];
    self2.latestSelectedDateObj = void 0;
    if (toInitial === true) {
      self2.currentYear = self2._initialDate.getFullYear();
      self2.currentMonth = self2._initialDate.getMonth();
    }
    if (self2.config.enableTime === true) {
      var _a = getDefaultHours(self2.config), hours = _a.hours, minutes = _a.minutes, seconds = _a.seconds;
      setHours(hours, minutes, seconds);
    }
    self2.redraw();
    if (triggerChangeEvent)
      triggerEvent("onChange");
  }
  function close() {
    self2.isOpen = false;
    if (!self2.isMobile) {
      if (self2.calendarContainer !== void 0) {
        self2.calendarContainer.classList.remove("open");
      }
      if (self2._input !== void 0) {
        self2._input.classList.remove("active");
      }
    }
    triggerEvent("onClose");
  }
  function destroy() {
    if (self2.config !== void 0)
      triggerEvent("onDestroy");
    for (var i = self2._handlers.length; i--; ) {
      self2._handlers[i].remove();
    }
    self2._handlers = [];
    if (self2.mobileInput) {
      if (self2.mobileInput.parentNode)
        self2.mobileInput.parentNode.removeChild(self2.mobileInput);
      self2.mobileInput = void 0;
    } else if (self2.calendarContainer && self2.calendarContainer.parentNode) {
      if (self2.config.static && self2.calendarContainer.parentNode) {
        var wrapper = self2.calendarContainer.parentNode;
        wrapper.lastChild && wrapper.removeChild(wrapper.lastChild);
        if (wrapper.parentNode) {
          while (wrapper.firstChild)
            wrapper.parentNode.insertBefore(wrapper.firstChild, wrapper);
          wrapper.parentNode.removeChild(wrapper);
        }
      } else
        self2.calendarContainer.parentNode.removeChild(self2.calendarContainer);
    }
    if (self2.altInput) {
      self2.input.type = "text";
      if (self2.altInput.parentNode)
        self2.altInput.parentNode.removeChild(self2.altInput);
      delete self2.altInput;
    }
    if (self2.input) {
      self2.input.type = self2.input._type;
      self2.input.classList.remove("flatpickr-input");
      self2.input.removeAttribute("readonly");
    }
    [
      "_showTimeInput",
      "latestSelectedDateObj",
      "_hideNextMonthArrow",
      "_hidePrevMonthArrow",
      "__hideNextMonthArrow",
      "__hidePrevMonthArrow",
      "isMobile",
      "isOpen",
      "selectedDateElem",
      "minDateHasTime",
      "maxDateHasTime",
      "days",
      "daysContainer",
      "_input",
      "_positionElement",
      "innerContainer",
      "rContainer",
      "monthNav",
      "todayDateElem",
      "calendarContainer",
      "weekdayContainer",
      "prevMonthNav",
      "nextMonthNav",
      "monthsDropdownContainer",
      "currentMonthElement",
      "currentYearElement",
      "navigationCurrentMonth",
      "selectedDateElem",
      "config"
    ].forEach(function(k) {
      try {
        delete self2[k];
      } catch (_) {
      }
    });
  }
  function isCalendarElem(elem) {
    return self2.calendarContainer.contains(elem);
  }
  function documentClick(e) {
    if (self2.isOpen && !self2.config.inline) {
      var eventTarget_1 = getEventTarget(e);
      var isCalendarElement = isCalendarElem(eventTarget_1);
      var isInput = eventTarget_1 === self2.input || eventTarget_1 === self2.altInput || self2.element.contains(eventTarget_1) || e.path && e.path.indexOf && (~e.path.indexOf(self2.input) || ~e.path.indexOf(self2.altInput));
      var lostFocus = !isInput && !isCalendarElement && !isCalendarElem(e.relatedTarget);
      var isIgnored = !self2.config.ignoredFocusElements.some(function(elem) {
        return elem.contains(eventTarget_1);
      });
      if (lostFocus && isIgnored) {
        if (self2.config.allowInput) {
          self2.setDate(self2._input.value, false, self2.config.altInput ? self2.config.altFormat : self2.config.dateFormat);
        }
        if (self2.timeContainer !== void 0 && self2.minuteElement !== void 0 && self2.hourElement !== void 0 && self2.input.value !== "" && self2.input.value !== void 0) {
          updateTime();
        }
        self2.close();
        if (self2.config && self2.config.mode === "range" && self2.selectedDates.length === 1)
          self2.clear(false);
      }
    }
  }
  function changeYear(newYear) {
    if (!newYear || self2.config.minDate && newYear < self2.config.minDate.getFullYear() || self2.config.maxDate && newYear > self2.config.maxDate.getFullYear())
      return;
    var newYearNum = newYear, isNewYear = self2.currentYear !== newYearNum;
    self2.currentYear = newYearNum || self2.currentYear;
    if (self2.config.maxDate && self2.currentYear === self2.config.maxDate.getFullYear()) {
      self2.currentMonth = Math.min(self2.config.maxDate.getMonth(), self2.currentMonth);
    } else if (self2.config.minDate && self2.currentYear === self2.config.minDate.getFullYear()) {
      self2.currentMonth = Math.max(self2.config.minDate.getMonth(), self2.currentMonth);
    }
    if (isNewYear) {
      self2.redraw();
      triggerEvent("onYearChange");
      buildMonthSwitch();
    }
  }
  function isEnabled(date, timeless) {
    var _a;
    if (timeless === void 0) {
      timeless = true;
    }
    var dateToCheck = self2.parseDate(date, void 0, timeless);
    if (self2.config.minDate && dateToCheck && compareDates(dateToCheck, self2.config.minDate, timeless !== void 0 ? timeless : !self2.minDateHasTime) < 0 || self2.config.maxDate && dateToCheck && compareDates(dateToCheck, self2.config.maxDate, timeless !== void 0 ? timeless : !self2.maxDateHasTime) > 0)
      return false;
    if (!self2.config.enable && self2.config.disable.length === 0)
      return true;
    if (dateToCheck === void 0)
      return false;
    var bool = !!self2.config.enable, array = (_a = self2.config.enable) !== null && _a !== void 0 ? _a : self2.config.disable;
    for (var i = 0, d = void 0; i < array.length; i++) {
      d = array[i];
      if (typeof d === "function" && d(dateToCheck))
        return bool;
      else if (d instanceof Date && dateToCheck !== void 0 && d.getTime() === dateToCheck.getTime())
        return bool;
      else if (typeof d === "string") {
        var parsed = self2.parseDate(d, void 0, true);
        return parsed && parsed.getTime() === dateToCheck.getTime() ? bool : !bool;
      } else if (typeof d === "object" && dateToCheck !== void 0 && d.from && d.to && dateToCheck.getTime() >= d.from.getTime() && dateToCheck.getTime() <= d.to.getTime())
        return bool;
    }
    return !bool;
  }
  function isInView(elem) {
    if (self2.daysContainer !== void 0)
      return elem.className.indexOf("hidden") === -1 && elem.className.indexOf("flatpickr-disabled") === -1 && self2.daysContainer.contains(elem);
    return false;
  }
  function onBlur(e) {
    var isInput = e.target === self2._input;
    var valueChanged = self2._input.value.trimEnd() !== getDateStr();
    if (isInput && valueChanged && !(e.relatedTarget && isCalendarElem(e.relatedTarget))) {
      self2.setDate(self2._input.value, true, e.target === self2.altInput ? self2.config.altFormat : self2.config.dateFormat);
    }
  }
  function onKeyDown(e) {
    var eventTarget = getEventTarget(e);
    var isInput = self2.config.wrap ? element.contains(eventTarget) : eventTarget === self2._input;
    var allowInput = self2.config.allowInput;
    var allowKeydown = self2.isOpen && (!allowInput || !isInput);
    var allowInlineKeydown = self2.config.inline && isInput && !allowInput;
    if (e.keyCode === 13 && isInput) {
      if (allowInput) {
        self2.setDate(self2._input.value, true, eventTarget === self2.altInput ? self2.config.altFormat : self2.config.dateFormat);
        self2.close();
        return eventTarget.blur();
      } else {
        self2.open();
      }
    } else if (isCalendarElem(eventTarget) || allowKeydown || allowInlineKeydown) {
      var isTimeObj = !!self2.timeContainer && self2.timeContainer.contains(eventTarget);
      switch (e.keyCode) {
        case 13:
          if (isTimeObj) {
            e.preventDefault();
            updateTime();
            focusAndClose();
          } else
            selectDate(e);
          break;
        case 27:
          e.preventDefault();
          focusAndClose();
          break;
        case 8:
        case 46:
          if (isInput && !self2.config.allowInput) {
            e.preventDefault();
            self2.clear();
          }
          break;
        case 37:
        case 39:
          if (!isTimeObj && !isInput) {
            e.preventDefault();
            var activeElement = getClosestActiveElement();
            if (self2.daysContainer !== void 0 && (allowInput === false || activeElement && isInView(activeElement))) {
              var delta_1 = e.keyCode === 39 ? 1 : -1;
              if (!e.ctrlKey)
                focusOnDay(void 0, delta_1);
              else {
                e.stopPropagation();
                changeMonth(delta_1);
                focusOnDay(getFirstAvailableDay(1), 0);
              }
            }
          } else if (self2.hourElement)
            self2.hourElement.focus();
          break;
        case 38:
        case 40:
          e.preventDefault();
          var delta = e.keyCode === 40 ? 1 : -1;
          if (self2.daysContainer && eventTarget.$i !== void 0 || eventTarget === self2.input || eventTarget === self2.altInput) {
            if (e.ctrlKey) {
              e.stopPropagation();
              changeYear(self2.currentYear - delta);
              focusOnDay(getFirstAvailableDay(1), 0);
            } else if (!isTimeObj)
              focusOnDay(void 0, delta * 7);
          } else if (eventTarget === self2.currentYearElement) {
            changeYear(self2.currentYear - delta);
          } else if (self2.config.enableTime) {
            if (!isTimeObj && self2.hourElement)
              self2.hourElement.focus();
            updateTime(e);
            self2._debouncedChange();
          }
          break;
        case 9:
          if (isTimeObj) {
            var elems = [
              self2.hourElement,
              self2.minuteElement,
              self2.secondElement,
              self2.amPM
            ].concat(self2.pluginElements).filter(function(x) {
              return x;
            });
            var i = elems.indexOf(eventTarget);
            if (i !== -1) {
              var target = elems[i + (e.shiftKey ? -1 : 1)];
              e.preventDefault();
              (target || self2._input).focus();
            }
          } else if (!self2.config.noCalendar && self2.daysContainer && self2.daysContainer.contains(eventTarget) && e.shiftKey) {
            e.preventDefault();
            self2._input.focus();
          }
          break;
        default:
          break;
      }
    }
    if (self2.amPM !== void 0 && eventTarget === self2.amPM) {
      switch (e.key) {
        case self2.l10n.amPM[0].charAt(0):
        case self2.l10n.amPM[0].charAt(0).toLowerCase():
          self2.amPM.textContent = self2.l10n.amPM[0];
          setHoursFromInputs();
          updateValue();
          break;
        case self2.l10n.amPM[1].charAt(0):
        case self2.l10n.amPM[1].charAt(0).toLowerCase():
          self2.amPM.textContent = self2.l10n.amPM[1];
          setHoursFromInputs();
          updateValue();
          break;
      }
    }
    if (isInput || isCalendarElem(eventTarget)) {
      triggerEvent("onKeyDown", e);
    }
  }
  function onMouseOver(elem, cellClass) {
    if (cellClass === void 0) {
      cellClass = "flatpickr-day";
    }
    if (self2.selectedDates.length !== 1 || elem && (!elem.classList.contains(cellClass) || elem.classList.contains("flatpickr-disabled")))
      return;
    var hoverDate = elem ? elem.dateObj.getTime() : self2.days.firstElementChild.dateObj.getTime(), initialDate = self2.parseDate(self2.selectedDates[0], void 0, true).getTime(), rangeStartDate = Math.min(hoverDate, self2.selectedDates[0].getTime()), rangeEndDate = Math.max(hoverDate, self2.selectedDates[0].getTime());
    var containsDisabled = false;
    var minRange = 0, maxRange = 0;
    for (var t = rangeStartDate; t < rangeEndDate; t += duration.DAY) {
      if (!isEnabled(new Date(t), true)) {
        containsDisabled = containsDisabled || t > rangeStartDate && t < rangeEndDate;
        if (t < initialDate && (!minRange || t > minRange))
          minRange = t;
        else if (t > initialDate && (!maxRange || t < maxRange))
          maxRange = t;
      }
    }
    var hoverableCells = Array.from(self2.rContainer.querySelectorAll("*:nth-child(-n+" + self2.config.showMonths + ") > ." + cellClass));
    hoverableCells.forEach(function(dayElem) {
      var date = dayElem.dateObj;
      var timestamp = date.getTime();
      var outOfRange = minRange > 0 && timestamp < minRange || maxRange > 0 && timestamp > maxRange;
      if (outOfRange) {
        dayElem.classList.add("notAllowed");
        ["inRange", "startRange", "endRange"].forEach(function(c) {
          dayElem.classList.remove(c);
        });
        return;
      } else if (containsDisabled && !outOfRange)
        return;
      ["startRange", "inRange", "endRange", "notAllowed"].forEach(function(c) {
        dayElem.classList.remove(c);
      });
      if (elem !== void 0) {
        elem.classList.add(hoverDate <= self2.selectedDates[0].getTime() ? "startRange" : "endRange");
        if (initialDate < hoverDate && timestamp === initialDate)
          dayElem.classList.add("startRange");
        else if (initialDate > hoverDate && timestamp === initialDate)
          dayElem.classList.add("endRange");
        if (timestamp >= minRange && (maxRange === 0 || timestamp <= maxRange) && isBetween(timestamp, initialDate, hoverDate))
          dayElem.classList.add("inRange");
      }
    });
  }
  function onResize() {
    if (self2.isOpen && !self2.config.static && !self2.config.inline)
      positionCalendar();
  }
  function open(e, positionElement) {
    if (positionElement === void 0) {
      positionElement = self2._positionElement;
    }
    if (self2.isMobile === true) {
      if (e) {
        e.preventDefault();
        var eventTarget = getEventTarget(e);
        if (eventTarget) {
          eventTarget.blur();
        }
      }
      if (self2.mobileInput !== void 0) {
        self2.mobileInput.focus();
        self2.mobileInput.click();
      }
      triggerEvent("onOpen");
      return;
    } else if (self2._input.disabled || self2.config.inline) {
      return;
    }
    var wasOpen = self2.isOpen;
    self2.isOpen = true;
    if (!wasOpen) {
      self2.calendarContainer.classList.add("open");
      self2._input.classList.add("active");
      triggerEvent("onOpen");
      positionCalendar(positionElement);
    }
    if (self2.config.enableTime === true && self2.config.noCalendar === true) {
      if (self2.config.allowInput === false && (e === void 0 || !self2.timeContainer.contains(e.relatedTarget))) {
        setTimeout(function() {
          return self2.hourElement.select();
        }, 50);
      }
    }
  }
  function minMaxDateSetter(type) {
    return function(date) {
      var dateObj = self2.config["_" + type + "Date"] = self2.parseDate(date, self2.config.dateFormat);
      var inverseDateObj = self2.config["_" + (type === "min" ? "max" : "min") + "Date"];
      if (dateObj !== void 0) {
        self2[type === "min" ? "minDateHasTime" : "maxDateHasTime"] = dateObj.getHours() > 0 || dateObj.getMinutes() > 0 || dateObj.getSeconds() > 0;
      }
      if (self2.selectedDates) {
        self2.selectedDates = self2.selectedDates.filter(function(d) {
          return isEnabled(d);
        });
        if (!self2.selectedDates.length && type === "min")
          setHoursFromDate(dateObj);
        updateValue();
      }
      if (self2.daysContainer) {
        redraw();
        if (dateObj !== void 0)
          self2.currentYearElement[type] = dateObj.getFullYear().toString();
        else
          self2.currentYearElement.removeAttribute(type);
        self2.currentYearElement.disabled = !!inverseDateObj && dateObj !== void 0 && inverseDateObj.getFullYear() === dateObj.getFullYear();
      }
    };
  }
  function parseConfig() {
    var boolOpts = [
      "wrap",
      "weekNumbers",
      "allowInput",
      "allowInvalidPreload",
      "clickOpens",
      "time_24hr",
      "enableTime",
      "noCalendar",
      "altInput",
      "shorthandCurrentMonth",
      "inline",
      "static",
      "enableSeconds",
      "disableMobile"
    ];
    var userConfig = __assign(__assign({}, JSON.parse(JSON.stringify(element.dataset || {}))), instanceConfig);
    var formats2 = {};
    self2.config.parseDate = userConfig.parseDate;
    self2.config.formatDate = userConfig.formatDate;
    Object.defineProperty(self2.config, "enable", {
      get: function() {
        return self2.config._enable;
      },
      set: function(dates) {
        self2.config._enable = parseDateRules(dates);
      }
    });
    Object.defineProperty(self2.config, "disable", {
      get: function() {
        return self2.config._disable;
      },
      set: function(dates) {
        self2.config._disable = parseDateRules(dates);
      }
    });
    var timeMode = userConfig.mode === "time";
    if (!userConfig.dateFormat && (userConfig.enableTime || timeMode)) {
      var defaultDateFormat = flatpickr.defaultConfig.dateFormat || defaults.dateFormat;
      formats2.dateFormat = userConfig.noCalendar || timeMode ? "H:i" + (userConfig.enableSeconds ? ":S" : "") : defaultDateFormat + " H:i" + (userConfig.enableSeconds ? ":S" : "");
    }
    if (userConfig.altInput && (userConfig.enableTime || timeMode) && !userConfig.altFormat) {
      var defaultAltFormat = flatpickr.defaultConfig.altFormat || defaults.altFormat;
      formats2.altFormat = userConfig.noCalendar || timeMode ? "h:i" + (userConfig.enableSeconds ? ":S K" : " K") : defaultAltFormat + (" h:i" + (userConfig.enableSeconds ? ":S" : "") + " K");
    }
    Object.defineProperty(self2.config, "minDate", {
      get: function() {
        return self2.config._minDate;
      },
      set: minMaxDateSetter("min")
    });
    Object.defineProperty(self2.config, "maxDate", {
      get: function() {
        return self2.config._maxDate;
      },
      set: minMaxDateSetter("max")
    });
    var minMaxTimeSetter = function(type) {
      return function(val) {
        self2.config[type === "min" ? "_minTime" : "_maxTime"] = self2.parseDate(val, "H:i:S");
      };
    };
    Object.defineProperty(self2.config, "minTime", {
      get: function() {
        return self2.config._minTime;
      },
      set: minMaxTimeSetter("min")
    });
    Object.defineProperty(self2.config, "maxTime", {
      get: function() {
        return self2.config._maxTime;
      },
      set: minMaxTimeSetter("max")
    });
    if (userConfig.mode === "time") {
      self2.config.noCalendar = true;
      self2.config.enableTime = true;
    }
    Object.assign(self2.config, formats2, userConfig);
    for (var i = 0; i < boolOpts.length; i++)
      self2.config[boolOpts[i]] = self2.config[boolOpts[i]] === true || self2.config[boolOpts[i]] === "true";
    HOOKS.filter(function(hook) {
      return self2.config[hook] !== void 0;
    }).forEach(function(hook) {
      self2.config[hook] = arrayify(self2.config[hook] || []).map(bindToInstance);
    });
    self2.isMobile = !self2.config.disableMobile && !self2.config.inline && self2.config.mode === "single" && !self2.config.disable.length && !self2.config.enable && !self2.config.weekNumbers && /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
    for (var i = 0; i < self2.config.plugins.length; i++) {
      var pluginConf = self2.config.plugins[i](self2) || {};
      for (var key2 in pluginConf) {
        if (HOOKS.indexOf(key2) > -1) {
          self2.config[key2] = arrayify(pluginConf[key2]).map(bindToInstance).concat(self2.config[key2]);
        } else if (typeof userConfig[key2] === "undefined")
          self2.config[key2] = pluginConf[key2];
      }
    }
    if (!userConfig.altInputClass) {
      self2.config.altInputClass = getInputElem().className + " " + self2.config.altInputClass;
    }
    triggerEvent("onParseConfig");
  }
  function getInputElem() {
    return self2.config.wrap ? element.querySelector("[data-input]") : element;
  }
  function setupLocale() {
    if (typeof self2.config.locale !== "object" && typeof flatpickr.l10ns[self2.config.locale] === "undefined")
      self2.config.errorHandler(new Error("flatpickr: invalid locale " + self2.config.locale));
    self2.l10n = __assign(__assign({}, flatpickr.l10ns.default), typeof self2.config.locale === "object" ? self2.config.locale : self2.config.locale !== "default" ? flatpickr.l10ns[self2.config.locale] : void 0);
    tokenRegex.D = "(" + self2.l10n.weekdays.shorthand.join("|") + ")";
    tokenRegex.l = "(" + self2.l10n.weekdays.longhand.join("|") + ")";
    tokenRegex.M = "(" + self2.l10n.months.shorthand.join("|") + ")";
    tokenRegex.F = "(" + self2.l10n.months.longhand.join("|") + ")";
    tokenRegex.K = "(" + self2.l10n.amPM[0] + "|" + self2.l10n.amPM[1] + "|" + self2.l10n.amPM[0].toLowerCase() + "|" + self2.l10n.amPM[1].toLowerCase() + ")";
    var userConfig = __assign(__assign({}, instanceConfig), JSON.parse(JSON.stringify(element.dataset || {})));
    if (userConfig.time_24hr === void 0 && flatpickr.defaultConfig.time_24hr === void 0) {
      self2.config.time_24hr = self2.l10n.time_24hr;
    }
    self2.formatDate = createDateFormatter(self2);
    self2.parseDate = createDateParser({ config: self2.config, l10n: self2.l10n });
  }
  function positionCalendar(customPositionElement) {
    if (typeof self2.config.position === "function") {
      return void self2.config.position(self2, customPositionElement);
    }
    if (self2.calendarContainer === void 0)
      return;
    triggerEvent("onPreCalendarPosition");
    var positionElement = customPositionElement || self2._positionElement;
    var calendarHeight = Array.prototype.reduce.call(self2.calendarContainer.children, (function(acc, child) {
      return acc + child.offsetHeight;
    }), 0), calendarWidth = self2.calendarContainer.offsetWidth, configPos = self2.config.position.split(" "), configPosVertical = configPos[0], configPosHorizontal = configPos.length > 1 ? configPos[1] : null, inputBounds = positionElement.getBoundingClientRect(), distanceFromBottom = window.innerHeight - inputBounds.bottom, showOnTop = configPosVertical === "above" || configPosVertical !== "below" && distanceFromBottom < calendarHeight && inputBounds.top > calendarHeight;
    var top = window.pageYOffset + inputBounds.top + (!showOnTop ? positionElement.offsetHeight + 2 : -calendarHeight - 2);
    toggleClass(self2.calendarContainer, "arrowTop", !showOnTop);
    toggleClass(self2.calendarContainer, "arrowBottom", showOnTop);
    if (self2.config.inline)
      return;
    var left = window.pageXOffset + inputBounds.left;
    var isCenter = false;
    var isRight = false;
    if (configPosHorizontal === "center") {
      left -= (calendarWidth - inputBounds.width) / 2;
      isCenter = true;
    } else if (configPosHorizontal === "right") {
      left -= calendarWidth - inputBounds.width;
      isRight = true;
    }
    toggleClass(self2.calendarContainer, "arrowLeft", !isCenter && !isRight);
    toggleClass(self2.calendarContainer, "arrowCenter", isCenter);
    toggleClass(self2.calendarContainer, "arrowRight", isRight);
    var right = window.document.body.offsetWidth - (window.pageXOffset + inputBounds.right);
    var rightMost = left + calendarWidth > window.document.body.offsetWidth;
    var centerMost = right + calendarWidth > window.document.body.offsetWidth;
    toggleClass(self2.calendarContainer, "rightMost", rightMost);
    if (self2.config.static)
      return;
    self2.calendarContainer.style.top = top + "px";
    if (!rightMost) {
      self2.calendarContainer.style.left = left + "px";
      self2.calendarContainer.style.right = "auto";
    } else if (!centerMost) {
      self2.calendarContainer.style.left = "auto";
      self2.calendarContainer.style.right = right + "px";
    } else {
      var doc = getDocumentStyleSheet();
      if (doc === void 0)
        return;
      var bodyWidth = window.document.body.offsetWidth;
      var centerLeft = Math.max(0, bodyWidth / 2 - calendarWidth / 2);
      var centerBefore = ".flatpickr-calendar.centerMost:before";
      var centerAfter = ".flatpickr-calendar.centerMost:after";
      var centerIndex = doc.cssRules.length;
      var centerStyle = "{left:" + inputBounds.left + "px;right:auto;}";
      toggleClass(self2.calendarContainer, "rightMost", false);
      toggleClass(self2.calendarContainer, "centerMost", true);
      doc.insertRule(centerBefore + "," + centerAfter + centerStyle, centerIndex);
      self2.calendarContainer.style.left = centerLeft + "px";
      self2.calendarContainer.style.right = "auto";
    }
  }
  function getDocumentStyleSheet() {
    var editableSheet = null;
    for (var i = 0; i < document.styleSheets.length; i++) {
      var sheet = document.styleSheets[i];
      if (!sheet.cssRules)
        continue;
      try {
        sheet.cssRules;
      } catch (err) {
        continue;
      }
      editableSheet = sheet;
      break;
    }
    return editableSheet != null ? editableSheet : createStyleSheet();
  }
  function createStyleSheet() {
    var style = document.createElement("style");
    document.head.appendChild(style);
    return style.sheet;
  }
  function redraw() {
    if (self2.config.noCalendar || self2.isMobile)
      return;
    buildMonthSwitch();
    updateNavigationCurrentMonth();
    buildDays();
  }
  function focusAndClose() {
    self2._input.focus();
    if (window.navigator.userAgent.indexOf("MSIE") !== -1 || navigator.msMaxTouchPoints !== void 0) {
      setTimeout(self2.close, 0);
    } else {
      self2.close();
    }
  }
  function selectDate(e) {
    e.preventDefault();
    e.stopPropagation();
    var isSelectable = function(day) {
      return day.classList && day.classList.contains("flatpickr-day") && !day.classList.contains("flatpickr-disabled") && !day.classList.contains("notAllowed");
    };
    var t = findParent(getEventTarget(e), isSelectable);
    if (t === void 0)
      return;
    var target = t;
    var selectedDate = self2.latestSelectedDateObj = new Date(target.dateObj.getTime());
    var shouldChangeMonth = (selectedDate.getMonth() < self2.currentMonth || selectedDate.getMonth() > self2.currentMonth + self2.config.showMonths - 1) && self2.config.mode !== "range";
    self2.selectedDateElem = target;
    if (self2.config.mode === "single")
      self2.selectedDates = [selectedDate];
    else if (self2.config.mode === "multiple") {
      var selectedIndex = isDateSelected(selectedDate);
      if (selectedIndex)
        self2.selectedDates.splice(parseInt(selectedIndex), 1);
      else
        self2.selectedDates.push(selectedDate);
    } else if (self2.config.mode === "range") {
      if (self2.selectedDates.length === 2) {
        self2.clear(false, false);
      }
      self2.latestSelectedDateObj = selectedDate;
      self2.selectedDates.push(selectedDate);
      if (compareDates(selectedDate, self2.selectedDates[0], true) !== 0)
        self2.selectedDates.sort(function(a, b) {
          return a.getTime() - b.getTime();
        });
    }
    setHoursFromInputs();
    if (shouldChangeMonth) {
      var isNewYear = self2.currentYear !== selectedDate.getFullYear();
      self2.currentYear = selectedDate.getFullYear();
      self2.currentMonth = selectedDate.getMonth();
      if (isNewYear) {
        triggerEvent("onYearChange");
        buildMonthSwitch();
      }
      triggerEvent("onMonthChange");
    }
    updateNavigationCurrentMonth();
    buildDays();
    updateValue();
    if (!shouldChangeMonth && self2.config.mode !== "range" && self2.config.showMonths === 1)
      focusOnDayElem(target);
    else if (self2.selectedDateElem !== void 0 && self2.hourElement === void 0) {
      self2.selectedDateElem && self2.selectedDateElem.focus();
    }
    if (self2.hourElement !== void 0)
      self2.hourElement !== void 0 && self2.hourElement.focus();
    if (self2.config.closeOnSelect) {
      var single = self2.config.mode === "single" && !self2.config.enableTime;
      var range = self2.config.mode === "range" && self2.selectedDates.length === 2 && !self2.config.enableTime;
      if (single || range) {
        focusAndClose();
      }
    }
    triggerChange();
  }
  var CALLBACKS = {
    locale: [setupLocale, updateWeekdays],
    showMonths: [buildMonths, setCalendarWidth, buildWeekdays],
    minDate: [jumpToDate],
    maxDate: [jumpToDate],
    positionElement: [updatePositionElement],
    clickOpens: [
      function() {
        if (self2.config.clickOpens === true) {
          bind(self2._input, "focus", self2.open);
          bind(self2._input, "click", self2.open);
        } else {
          self2._input.removeEventListener("focus", self2.open);
          self2._input.removeEventListener("click", self2.open);
        }
      }
    ]
  };
  function set(option, value) {
    if (option !== null && typeof option === "object") {
      Object.assign(self2.config, option);
      for (var key2 in option) {
        if (CALLBACKS[key2] !== void 0)
          CALLBACKS[key2].forEach(function(x) {
            return x();
          });
      }
    } else {
      self2.config[option] = value;
      if (CALLBACKS[option] !== void 0)
        CALLBACKS[option].forEach(function(x) {
          return x();
        });
      else if (HOOKS.indexOf(option) > -1)
        self2.config[option] = arrayify(value);
    }
    self2.redraw();
    updateValue(true);
  }
  function setSelectedDate(inputDate, format) {
    var dates = [];
    if (inputDate instanceof Array)
      dates = inputDate.map(function(d) {
        return self2.parseDate(d, format);
      });
    else if (inputDate instanceof Date || typeof inputDate === "number")
      dates = [self2.parseDate(inputDate, format)];
    else if (typeof inputDate === "string") {
      switch (self2.config.mode) {
        case "single":
        case "time":
          dates = [self2.parseDate(inputDate, format)];
          break;
        case "multiple":
          dates = inputDate.split(self2.config.conjunction).map(function(date) {
            return self2.parseDate(date, format);
          });
          break;
        case "range":
          dates = inputDate.split(self2.l10n.rangeSeparator).map(function(date) {
            return self2.parseDate(date, format);
          });
          break;
        default:
          break;
      }
    } else
      self2.config.errorHandler(new Error("Invalid date supplied: " + JSON.stringify(inputDate)));
    self2.selectedDates = self2.config.allowInvalidPreload ? dates : dates.filter(function(d) {
      return d instanceof Date && isEnabled(d, false);
    });
    if (self2.config.mode === "range")
      self2.selectedDates.sort(function(a, b) {
        return a.getTime() - b.getTime();
      });
  }
  function setDate(date, triggerChange2, format) {
    if (triggerChange2 === void 0) {
      triggerChange2 = false;
    }
    if (format === void 0) {
      format = self2.config.dateFormat;
    }
    if (date !== 0 && !date || date instanceof Array && date.length === 0)
      return self2.clear(triggerChange2);
    setSelectedDate(date, format);
    self2.latestSelectedDateObj = self2.selectedDates[self2.selectedDates.length - 1];
    self2.redraw();
    jumpToDate(void 0, triggerChange2);
    setHoursFromDate();
    if (self2.selectedDates.length === 0) {
      self2.clear(false);
    }
    updateValue(triggerChange2);
    if (triggerChange2)
      triggerEvent("onChange");
  }
  function parseDateRules(arr) {
    return arr.slice().map(function(rule) {
      if (typeof rule === "string" || typeof rule === "number" || rule instanceof Date) {
        return self2.parseDate(rule, void 0, true);
      } else if (rule && typeof rule === "object" && rule.from && rule.to)
        return {
          from: self2.parseDate(rule.from, void 0),
          to: self2.parseDate(rule.to, void 0)
        };
      return rule;
    }).filter(function(x) {
      return x;
    });
  }
  function setupDates() {
    self2.selectedDates = [];
    self2.now = self2.parseDate(self2.config.now) || /* @__PURE__ */ new Date();
    var preloadedDate = self2.config.defaultDate || ((self2.input.nodeName === "INPUT" || self2.input.nodeName === "TEXTAREA") && self2.input.placeholder && self2.input.value === self2.input.placeholder ? null : self2.input.value);
    if (preloadedDate)
      setSelectedDate(preloadedDate, self2.config.dateFormat);
    self2._initialDate = self2.selectedDates.length > 0 ? self2.selectedDates[0] : self2.config.minDate && self2.config.minDate.getTime() > self2.now.getTime() ? self2.config.minDate : self2.config.maxDate && self2.config.maxDate.getTime() < self2.now.getTime() ? self2.config.maxDate : self2.now;
    self2.currentYear = self2._initialDate.getFullYear();
    self2.currentMonth = self2._initialDate.getMonth();
    if (self2.selectedDates.length > 0)
      self2.latestSelectedDateObj = self2.selectedDates[0];
    if (self2.config.minTime !== void 0)
      self2.config.minTime = self2.parseDate(self2.config.minTime, "H:i");
    if (self2.config.maxTime !== void 0)
      self2.config.maxTime = self2.parseDate(self2.config.maxTime, "H:i");
    self2.minDateHasTime = !!self2.config.minDate && (self2.config.minDate.getHours() > 0 || self2.config.minDate.getMinutes() > 0 || self2.config.minDate.getSeconds() > 0);
    self2.maxDateHasTime = !!self2.config.maxDate && (self2.config.maxDate.getHours() > 0 || self2.config.maxDate.getMinutes() > 0 || self2.config.maxDate.getSeconds() > 0);
  }
  function setupInputs() {
    self2.input = getInputElem();
    if (!self2.input) {
      self2.config.errorHandler(new Error("Invalid input element specified"));
      return;
    }
    self2.input._type = self2.input.type;
    self2.input.type = "text";
    self2.input.classList.add("flatpickr-input");
    self2._input = self2.input;
    if (self2.config.altInput) {
      self2.altInput = createElement(self2.input.nodeName, self2.config.altInputClass);
      self2._input = self2.altInput;
      self2.altInput.placeholder = self2.input.placeholder;
      self2.altInput.disabled = self2.input.disabled;
      self2.altInput.required = self2.input.required;
      self2.altInput.tabIndex = self2.input.tabIndex;
      self2.altInput.type = "text";
      self2.input.setAttribute("type", "hidden");
      if (!self2.config.static && self2.input.parentNode)
        self2.input.parentNode.insertBefore(self2.altInput, self2.input.nextSibling);
    }
    if (!self2.config.allowInput)
      self2._input.setAttribute("readonly", "readonly");
    updatePositionElement();
  }
  function updatePositionElement() {
    self2._positionElement = self2.config.positionElement || self2._input;
  }
  function setupMobile() {
    var inputType = self2.config.enableTime ? self2.config.noCalendar ? "time" : "datetime-local" : "date";
    self2.mobileInput = createElement("input", self2.input.className + " flatpickr-mobile");
    self2.mobileInput.tabIndex = 1;
    self2.mobileInput.type = inputType;
    self2.mobileInput.disabled = self2.input.disabled;
    self2.mobileInput.required = self2.input.required;
    self2.mobileInput.placeholder = self2.input.placeholder;
    self2.mobileFormatStr = inputType === "datetime-local" ? "Y-m-d\\TH:i:S" : inputType === "date" ? "Y-m-d" : "H:i:S";
    if (self2.selectedDates.length > 0) {
      self2.mobileInput.defaultValue = self2.mobileInput.value = self2.formatDate(self2.selectedDates[0], self2.mobileFormatStr);
    }
    if (self2.config.minDate)
      self2.mobileInput.min = self2.formatDate(self2.config.minDate, "Y-m-d");
    if (self2.config.maxDate)
      self2.mobileInput.max = self2.formatDate(self2.config.maxDate, "Y-m-d");
    if (self2.input.getAttribute("step"))
      self2.mobileInput.step = String(self2.input.getAttribute("step"));
    self2.input.type = "hidden";
    if (self2.altInput !== void 0)
      self2.altInput.type = "hidden";
    try {
      if (self2.input.parentNode)
        self2.input.parentNode.insertBefore(self2.mobileInput, self2.input.nextSibling);
    } catch (_a) {
    }
    bind(self2.mobileInput, "change", function(e) {
      self2.setDate(getEventTarget(e).value, false, self2.mobileFormatStr);
      triggerEvent("onChange");
      triggerEvent("onClose");
    });
  }
  function toggle(e) {
    if (self2.isOpen === true)
      return self2.close();
    self2.open(e);
  }
  function triggerEvent(event, data) {
    if (self2.config === void 0)
      return;
    var hooks = self2.config[event];
    if (hooks !== void 0 && hooks.length > 0) {
      for (var i = 0; hooks[i] && i < hooks.length; i++)
        hooks[i](self2.selectedDates, self2.input.value, self2, data);
    }
    if (event === "onChange") {
      self2.input.dispatchEvent(createEvent("change"));
      self2.input.dispatchEvent(createEvent("input"));
    }
  }
  function createEvent(name) {
    var e = document.createEvent("Event");
    e.initEvent(name, true, true);
    return e;
  }
  function isDateSelected(date) {
    for (var i = 0; i < self2.selectedDates.length; i++) {
      var selectedDate = self2.selectedDates[i];
      if (selectedDate instanceof Date && compareDates(selectedDate, date) === 0)
        return "" + i;
    }
    return false;
  }
  function isDateInRange(date) {
    if (self2.config.mode !== "range" || self2.selectedDates.length < 2)
      return false;
    return compareDates(date, self2.selectedDates[0]) >= 0 && compareDates(date, self2.selectedDates[1]) <= 0;
  }
  function updateNavigationCurrentMonth() {
    if (self2.config.noCalendar || self2.isMobile || !self2.monthNav)
      return;
    self2.yearElements.forEach(function(yearElement, i) {
      var d = new Date(self2.currentYear, self2.currentMonth, 1);
      d.setMonth(self2.currentMonth + i);
      if (self2.config.showMonths > 1 || self2.config.monthSelectorType === "static") {
        self2.monthElements[i].textContent = monthToStr(d.getMonth(), self2.config.shorthandCurrentMonth, self2.l10n) + " ";
      } else {
        self2.monthsDropdownContainer.value = d.getMonth().toString();
      }
      yearElement.value = d.getFullYear().toString();
    });
    self2._hidePrevMonthArrow = self2.config.minDate !== void 0 && (self2.currentYear === self2.config.minDate.getFullYear() ? self2.currentMonth <= self2.config.minDate.getMonth() : self2.currentYear < self2.config.minDate.getFullYear());
    self2._hideNextMonthArrow = self2.config.maxDate !== void 0 && (self2.currentYear === self2.config.maxDate.getFullYear() ? self2.currentMonth + 1 > self2.config.maxDate.getMonth() : self2.currentYear > self2.config.maxDate.getFullYear());
  }
  function getDateStr(specificFormat) {
    var format = specificFormat || (self2.config.altInput ? self2.config.altFormat : self2.config.dateFormat);
    return self2.selectedDates.map(function(dObj) {
      return self2.formatDate(dObj, format);
    }).filter(function(d, i, arr) {
      return self2.config.mode !== "range" || self2.config.enableTime || arr.indexOf(d) === i;
    }).join(self2.config.mode !== "range" ? self2.config.conjunction : self2.l10n.rangeSeparator);
  }
  function updateValue(triggerChange2) {
    if (triggerChange2 === void 0) {
      triggerChange2 = true;
    }
    if (self2.mobileInput !== void 0 && self2.mobileFormatStr) {
      self2.mobileInput.value = self2.latestSelectedDateObj !== void 0 ? self2.formatDate(self2.latestSelectedDateObj, self2.mobileFormatStr) : "";
    }
    self2.input.value = getDateStr(self2.config.dateFormat);
    if (self2.altInput !== void 0) {
      self2.altInput.value = getDateStr(self2.config.altFormat);
    }
    if (triggerChange2 !== false)
      triggerEvent("onValueUpdate");
  }
  function onMonthNavClick(e) {
    var eventTarget = getEventTarget(e);
    var isPrevMonth = self2.prevMonthNav.contains(eventTarget);
    var isNextMonth = self2.nextMonthNav.contains(eventTarget);
    if (isPrevMonth || isNextMonth) {
      changeMonth(isPrevMonth ? -1 : 1);
    } else if (self2.yearElements.indexOf(eventTarget) >= 0) {
      eventTarget.select();
    } else if (eventTarget.classList.contains("arrowUp")) {
      self2.changeYear(self2.currentYear + 1);
    } else if (eventTarget.classList.contains("arrowDown")) {
      self2.changeYear(self2.currentYear - 1);
    }
  }
  function timeWrapper(e) {
    e.preventDefault();
    var isKeyDown = e.type === "keydown", eventTarget = getEventTarget(e), input = eventTarget;
    if (self2.amPM !== void 0 && eventTarget === self2.amPM) {
      self2.amPM.textContent = self2.l10n.amPM[int(self2.amPM.textContent === self2.l10n.amPM[0])];
    }
    var min = parseFloat(input.getAttribute("min")), max = parseFloat(input.getAttribute("max")), step = parseFloat(input.getAttribute("step")), curValue = parseInt(input.value, 10), delta = e.delta || (isKeyDown ? e.which === 38 ? 1 : -1 : 0);
    var newValue = curValue + step * delta;
    if (typeof input.value !== "undefined" && input.value.length === 2) {
      var isHourElem = input === self2.hourElement, isMinuteElem = input === self2.minuteElement;
      if (newValue < min) {
        newValue = max + newValue + int(!isHourElem) + (int(isHourElem) && int(!self2.amPM));
        if (isMinuteElem)
          incrementNumInput(void 0, -1, self2.hourElement);
      } else if (newValue > max) {
        newValue = input === self2.hourElement ? newValue - max - int(!self2.amPM) : min;
        if (isMinuteElem)
          incrementNumInput(void 0, 1, self2.hourElement);
      }
      if (self2.amPM && isHourElem && (step === 1 ? newValue + curValue === 23 : Math.abs(newValue - curValue) > step)) {
        self2.amPM.textContent = self2.l10n.amPM[int(self2.amPM.textContent === self2.l10n.amPM[0])];
      }
      input.value = pad(newValue);
    }
  }
  init();
  return self2;
}
function _flatpickr(nodeList, config) {
  var nodes = Array.prototype.slice.call(nodeList).filter(function(x) {
    return x instanceof HTMLElement;
  });
  var instances = [];
  for (var i = 0; i < nodes.length; i++) {
    var node = nodes[i];
    try {
      if (node.getAttribute("data-fp-omit") !== null)
        continue;
      if (node._flatpickr !== void 0) {
        node._flatpickr.destroy();
        node._flatpickr = void 0;
      }
      node._flatpickr = FlatpickrInstance(node, config || {});
      instances.push(node._flatpickr);
    } catch (e) {
      console.error(e);
    }
  }
  return instances.length === 1 ? instances[0] : instances;
}
if (typeof HTMLElement !== "undefined" && typeof HTMLCollection !== "undefined" && typeof NodeList !== "undefined") {
  HTMLCollection.prototype.flatpickr = NodeList.prototype.flatpickr = function(config) {
    return _flatpickr(this, config);
  };
  HTMLElement.prototype.flatpickr = function(config) {
    return _flatpickr([this], config);
  };
}
var flatpickr = function(selector, config) {
  if (typeof selector === "string") {
    return _flatpickr(window.document.querySelectorAll(selector), config);
  } else if (selector instanceof Node) {
    return _flatpickr([selector], config);
  } else {
    return _flatpickr(selector, config);
  }
};
flatpickr.defaultConfig = {};
flatpickr.l10ns = {
  en: __assign({}, default_default),
  default: __assign({}, default_default)
};
flatpickr.localize = function(l10n) {
  flatpickr.l10ns.default = __assign(__assign({}, flatpickr.l10ns.default), l10n);
};
flatpickr.setDefaults = function(config) {
  flatpickr.defaultConfig = __assign(__assign({}, flatpickr.defaultConfig), config);
};
flatpickr.parseDate = createDateParser({});
flatpickr.formatDate = createDateFormatter({});
flatpickr.compareDates = compareDates;
if (typeof jQuery !== "undefined" && typeof jQuery.fn !== "undefined") {
  jQuery.fn.flatpickr = function(config) {
    return _flatpickr(this, config);
  };
}
Date.prototype.fp_incr = function(days) {
  return new Date(this.getFullYear(), this.getMonth(), this.getDate() + (typeof days === "string" ? parseInt(days, 10) : days));
};
if (typeof window !== "undefined") {
  window.flatpickr = flatpickr;
}
var esm_default = flatpickr;

// ../../apps/obsidian-dayisle/main.mjs
var import_zh = __toESM(require_zh(), 1);

// ../../apps/obsidian-dayisle/glass-calendar.css
var glass_calendar_default = ".dayisle-panel input,.dayisle-panel textarea,.dayisle-review input,.dayisle-review textarea{font-size:16px;box-sizing:border-box;max-width:100%}\n.dayisle-review textarea{width:100%;min-height:160px;resize:vertical}\n.dayisle-calendar{position:absolute;display:none;visibility:hidden;opacity:0;text-align:center;direction:ltr;box-sizing:border-box;line-height:24px;font-size:16px;touch-action:manipulation}\n.dayisle-calendar.open{display:block;visibility:visible;opacity:1;z-index:100000;max-width:calc(100vw - 24px)}\n.dayisle-calendar .flatpickr-months{display:flex;position:relative;height:40px;align-items:center}\n.dayisle-calendar .flatpickr-month{flex:1;text-align:center}\n.dayisle-calendar .flatpickr-current-month{display:flex;justify-content:center;gap:8px;align-items:center;font-weight:600}\n.dayisle-calendar .numInputWrapper{display:inline-flex;width:78px}.dayisle-calendar .numInputWrapper input{width:78px;height:32px;border:0;background:transparent;padding:4px}.dayisle-calendar .numInputWrapper span{display:none}\n.dayisle-calendar .flatpickr-prev-month,.dayisle-calendar .flatpickr-next-month{position:absolute;top:0;width:36px;height:36px;display:flex;justify-content:center;align-items:center;cursor:pointer}\n.dayisle-calendar .flatpickr-prev-month{left:0}.dayisle-calendar .flatpickr-next-month{right:0}.dayisle-calendar .flatpickr-prev-month svg,.dayisle-calendar .flatpickr-next-month svg{width:14px;height:14px}\n.dayisle-calendar .flatpickr-disabled{opacity:.35;pointer-events:none}.dayisle-calendar .flatpickr-innerContainer{display:flex}.dayisle-calendar .flatpickr-rContainer{flex:1}\n.dayisle-calendar .flatpickr-weekdaycontainer,.dayisle-calendar .dayContainer{display:flex;flex-wrap:wrap}.dayisle-calendar .flatpickr-weekday{flex:1;text-align:center;font-size:13px;line-height:32px}\n.dayisle-calendar .flatpickr-day{display:inline-flex;align-items:center;justify-content:center;box-sizing:border-box;border:1px solid transparent;cursor:pointer}.dayisle-calendar .flatpickr-day.today{border-color:var(--background-modifier-border)}\n.dayisle-review .dayisle-date{display:block;width:100%;min-height:44px;border:1px solid var(--background-modifier-border);border-radius:18px;background:color-mix(in srgb,var(--background-primary) 80%,transparent);backdrop-filter:blur(16px);color:var(--text-normal);box-shadow:inset 0 1px 0 #ffffff45,0 5px 18px #0000000d}\n.dayisle-calendar.flatpickr-calendar{width:min(308px,calc(100vw - 32px));padding:10px 5px;border:1px solid var(--background-modifier-border);border-radius:24px;background:color-mix(in srgb,var(--background-primary) 88%,transparent);color:var(--text-normal);backdrop-filter:blur(22px) saturate(1.2);box-shadow:inset 0 1px 0 #ffffff55,0 16px 48px #00000025;max-height:min(440px,65dvh);overflow:auto}\n.dayisle-calendar .flatpickr-months,.dayisle-calendar .flatpickr-month,.dayisle-calendar .flatpickr-weekdays,.dayisle-calendar span.flatpickr-weekday,.dayisle-calendar .flatpickr-current-month{background:transparent;color:var(--text-normal)}\n.dayisle-calendar .flatpickr-day{color:var(--text-normal);border-radius:14px;height:38px;line-height:36px;transition:background .16s ease,box-shadow .16s ease}\n.dayisle-calendar .flatpickr-day.prevMonthDay,.dayisle-calendar .flatpickr-day.nextMonthDay{color:var(--text-muted)}\n.dayisle-calendar .flatpickr-day.selected{background:color-mix(in srgb,var(--interactive-accent) 24%,var(--background-primary));border-color:var(--interactive-accent);color:var(--text-normal);box-shadow:inset 0 1px 0 #ffffff66,0 3px 12px #00000016}\n.dayisle-calendar .flatpickr-day:hover,.dayisle-calendar .flatpickr-day:focus{background:color-mix(in srgb,var(--interactive-accent) 15%,transparent);border-color:transparent}\n.dayisle-calendar .flatpickr-prev-month,.dayisle-calendar .flatpickr-next-month{fill:var(--text-normal);color:var(--text-normal)}\n.dayisle-calendar .flatpickr-innerContainer,.dayisle-calendar .flatpickr-rContainer,.dayisle-calendar .dayContainer,.dayisle-calendar .flatpickr-days{width:100%;min-width:0;max-width:100%}\n.dayisle-calendar .flatpickr-day{max-width:14.2857%;flex-basis:14.2857%}\n.dayisle-calendar .numInputWrapper input{font-size:16px;color:var(--text-normal)}\n.dayisle-calendar:before,.dayisle-calendar:after{display:none}\n.dayisle-date:focus-visible,.dayisle-calendar .flatpickr-day:focus-visible{outline:2px solid var(--interactive-accent);outline-offset:2px}\n@media(prefers-reduced-motion:reduce){.dayisle-calendar *{animation:none!important;transition:none!important}}\n";

// platform.mjs
var import_buffer = __toESM(require_buffer(), 1);

// node_modules/@noble/hashes/utils.js
function isBytes(a) {
  return a instanceof Uint8Array || ArrayBuffer.isView(a) && a.constructor.name === "Uint8Array";
}
function abytes(value, length, title = "") {
  const bytes = isBytes(value);
  const len = value?.length;
  const needsLen = length !== void 0;
  if (!bytes || needsLen && len !== length) {
    const prefix = title && `"${title}" `;
    const ofLen = needsLen ? ` of length ${length}` : "";
    const got = bytes ? `length=${len}` : `type=${typeof value}`;
    throw new Error(prefix + "expected Uint8Array" + ofLen + ", got " + got);
  }
  return value;
}
function aexists(instance, checkFinished = true) {
  if (instance.destroyed)
    throw new Error("Hash instance has been destroyed");
  if (checkFinished && instance.finished)
    throw new Error("Hash#digest() has already been called");
}
function aoutput(out, instance) {
  abytes(out, void 0, "digestInto() output");
  const min = instance.outputLen;
  if (out.length < min) {
    throw new Error('"digestInto() output" expected to be of length >=' + min);
  }
}
function clean(...arrays) {
  for (let i = 0; i < arrays.length; i++) {
    arrays[i].fill(0);
  }
}
function createView(arr) {
  return new DataView(arr.buffer, arr.byteOffset, arr.byteLength);
}
function rotr(word, shift) {
  return word << 32 - shift | word >>> shift;
}
function createHasher(hashCons, info = {}) {
  const hashC = (msg, opts) => hashCons(opts).update(msg).digest();
  const tmp = hashCons(void 0);
  hashC.outputLen = tmp.outputLen;
  hashC.blockLen = tmp.blockLen;
  hashC.create = (opts) => hashCons(opts);
  Object.assign(hashC, info);
  return Object.freeze(hashC);
}
var oidNist = (suffix) => ({
  oid: Uint8Array.from([6, 9, 96, 134, 72, 1, 101, 3, 4, 2, suffix])
});

// node_modules/@noble/hashes/_md.js
function Chi(a, b, c) {
  return a & b ^ ~a & c;
}
function Maj(a, b, c) {
  return a & b ^ a & c ^ b & c;
}
var HashMD = class {
  blockLen;
  outputLen;
  padOffset;
  isLE;
  // For partial updates less than block size
  buffer;
  view;
  finished = false;
  length = 0;
  pos = 0;
  destroyed = false;
  constructor(blockLen, outputLen, padOffset, isLE) {
    this.blockLen = blockLen;
    this.outputLen = outputLen;
    this.padOffset = padOffset;
    this.isLE = isLE;
    this.buffer = new Uint8Array(blockLen);
    this.view = createView(this.buffer);
  }
  update(data) {
    aexists(this);
    abytes(data);
    const { view, buffer, blockLen } = this;
    const len = data.length;
    for (let pos = 0; pos < len; ) {
      const take = Math.min(blockLen - this.pos, len - pos);
      if (take === blockLen) {
        const dataView = createView(data);
        for (; blockLen <= len - pos; pos += blockLen)
          this.process(dataView, pos);
        continue;
      }
      buffer.set(data.subarray(pos, pos + take), this.pos);
      this.pos += take;
      pos += take;
      if (this.pos === blockLen) {
        this.process(view, 0);
        this.pos = 0;
      }
    }
    this.length += data.length;
    this.roundClean();
    return this;
  }
  digestInto(out) {
    aexists(this);
    aoutput(out, this);
    this.finished = true;
    const { buffer, view, blockLen, isLE } = this;
    let { pos } = this;
    buffer[pos++] = 128;
    clean(this.buffer.subarray(pos));
    if (this.padOffset > blockLen - pos) {
      this.process(view, 0);
      pos = 0;
    }
    for (let i = pos; i < blockLen; i++)
      buffer[i] = 0;
    view.setBigUint64(blockLen - 8, BigInt(this.length * 8), isLE);
    this.process(view, 0);
    const oview = createView(out);
    const len = this.outputLen;
    if (len % 4)
      throw new Error("_sha2: outputLen must be aligned to 32bit");
    const outLen = len / 4;
    const state = this.get();
    if (outLen > state.length)
      throw new Error("_sha2: outputLen bigger than state");
    for (let i = 0; i < outLen; i++)
      oview.setUint32(4 * i, state[i], isLE);
  }
  digest() {
    const { buffer, outputLen } = this;
    this.digestInto(buffer);
    const res = buffer.slice(0, outputLen);
    this.destroy();
    return res;
  }
  _cloneInto(to) {
    to ||= new this.constructor();
    to.set(...this.get());
    const { blockLen, buffer, length, finished, destroyed, pos } = this;
    to.destroyed = destroyed;
    to.finished = finished;
    to.length = length;
    to.pos = pos;
    if (length % blockLen)
      to.buffer.set(buffer);
    return to;
  }
  clone() {
    return this._cloneInto();
  }
};
var SHA256_IV = /* @__PURE__ */ Uint32Array.from([
  1779033703,
  3144134277,
  1013904242,
  2773480762,
  1359893119,
  2600822924,
  528734635,
  1541459225
]);

// node_modules/@noble/hashes/sha2.js
var SHA256_K = /* @__PURE__ */ Uint32Array.from([
  1116352408,
  1899447441,
  3049323471,
  3921009573,
  961987163,
  1508970993,
  2453635748,
  2870763221,
  3624381080,
  310598401,
  607225278,
  1426881987,
  1925078388,
  2162078206,
  2614888103,
  3248222580,
  3835390401,
  4022224774,
  264347078,
  604807628,
  770255983,
  1249150122,
  1555081692,
  1996064986,
  2554220882,
  2821834349,
  2952996808,
  3210313671,
  3336571891,
  3584528711,
  113926993,
  338241895,
  666307205,
  773529912,
  1294757372,
  1396182291,
  1695183700,
  1986661051,
  2177026350,
  2456956037,
  2730485921,
  2820302411,
  3259730800,
  3345764771,
  3516065817,
  3600352804,
  4094571909,
  275423344,
  430227734,
  506948616,
  659060556,
  883997877,
  958139571,
  1322822218,
  1537002063,
  1747873779,
  1955562222,
  2024104815,
  2227730452,
  2361852424,
  2428436474,
  2756734187,
  3204031479,
  3329325298
]);
var SHA256_W = /* @__PURE__ */ new Uint32Array(64);
var SHA2_32B = class extends HashMD {
  constructor(outputLen) {
    super(64, outputLen, 8, false);
  }
  get() {
    const { A, B, C, D, E, F, G, H } = this;
    return [A, B, C, D, E, F, G, H];
  }
  // prettier-ignore
  set(A, B, C, D, E, F, G, H) {
    this.A = A | 0;
    this.B = B | 0;
    this.C = C | 0;
    this.D = D | 0;
    this.E = E | 0;
    this.F = F | 0;
    this.G = G | 0;
    this.H = H | 0;
  }
  process(view, offset) {
    for (let i = 0; i < 16; i++, offset += 4)
      SHA256_W[i] = view.getUint32(offset, false);
    for (let i = 16; i < 64; i++) {
      const W15 = SHA256_W[i - 15];
      const W2 = SHA256_W[i - 2];
      const s0 = rotr(W15, 7) ^ rotr(W15, 18) ^ W15 >>> 3;
      const s1 = rotr(W2, 17) ^ rotr(W2, 19) ^ W2 >>> 10;
      SHA256_W[i] = s1 + SHA256_W[i - 7] + s0 + SHA256_W[i - 16] | 0;
    }
    let { A, B, C, D, E, F, G, H } = this;
    for (let i = 0; i < 64; i++) {
      const sigma1 = rotr(E, 6) ^ rotr(E, 11) ^ rotr(E, 25);
      const T1 = H + sigma1 + Chi(E, F, G) + SHA256_K[i] + SHA256_W[i] | 0;
      const sigma0 = rotr(A, 2) ^ rotr(A, 13) ^ rotr(A, 22);
      const T2 = sigma0 + Maj(A, B, C) | 0;
      H = G;
      G = F;
      F = E;
      E = D + T1 | 0;
      D = C;
      C = B;
      B = A;
      A = T1 + T2 | 0;
    }
    A = A + this.A | 0;
    B = B + this.B | 0;
    C = C + this.C | 0;
    D = D + this.D | 0;
    E = E + this.E | 0;
    F = F + this.F | 0;
    G = G + this.G | 0;
    H = H + this.H | 0;
    this.set(A, B, C, D, E, F, G, H);
  }
  roundClean() {
    clean(SHA256_W);
  }
  destroy() {
    this.set(0, 0, 0, 0, 0, 0, 0, 0);
    clean(this.buffer);
  }
};
var _SHA256 = class extends SHA2_32B {
  // We cannot use array here since array allows indexing by variable
  // which means optimizer/compiler cannot use registers.
  A = SHA256_IV[0] | 0;
  B = SHA256_IV[1] | 0;
  C = SHA256_IV[2] | 0;
  D = SHA256_IV[3] | 0;
  E = SHA256_IV[4] | 0;
  F = SHA256_IV[5] | 0;
  G = SHA256_IV[6] | 0;
  H = SHA256_IV[7] | 0;
  constructor() {
    super(32);
  }
};
var sha256 = /* @__PURE__ */ createHasher(
  () => new _SHA256(),
  /* @__PURE__ */ oidNist(1)
);

// platform.mjs
globalThis.Buffer ??= import_buffer.Buffer;
var StrictUTF8Decoder = class {
  constructor(encoding = "utf-8", options = {}) {
    if (!/^utf-?8$/i.test(encoding) || options.fatal !== true) throw Error("Strict UTF-8 only");
    this.keepBOM = options.ignoreBOM === true;
  }
  decode(input) {
    const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
    let output = "";
    for (let i = 0; i < bytes.length; ) {
      const first = bytes[i++];
      let count, point, minimum;
      if (first < 128) {
        output += String.fromCharCode(first);
        continue;
      }
      if (first >= 194 && first <= 223) {
        count = 1;
        point = first & 31;
        minimum = 128;
      } else if (first >= 224 && first <= 239) {
        count = 2;
        point = first & 15;
        minimum = 2048;
      } else if (first >= 240 && first <= 244) {
        count = 3;
        point = first & 7;
        minimum = 65536;
      } else throw Error("Invalid UTF-8");
      if (i + count > bytes.length) throw Error("Truncated UTF-8");
      for (let j = 0; j < count; j++) {
        const next = bytes[i++];
        if ((next & 192) !== 128) throw Error("Invalid continuation");
        point = point << 6 | next & 63;
      }
      if (point < minimum || point > 1114111 || point >= 55296 && point <= 57343) throw Error("Invalid code point");
      output += String.fromCodePoint(point);
    }
    return !this.keepBOM && output.charCodeAt(0) === 65279 ? output.slice(1) : output;
  }
};
globalThis.TextDecoder ??= StrictUTF8Decoder;
globalThis.structuredClone ??= (value) => JSON.parse(JSON.stringify(value));
function createHash(algorithm) {
  if (algorithm !== "sha256") throw Error("SHA-256 only");
  let input;
  return { update(bytes) {
    if (input !== void 0) throw Error("Single update only");
    input = bytes;
    return this;
  }, digest(encoding) {
    if (encoding !== "hex") throw Error("Hex only");
    return Array.from(sha256(input)).map((b) => b.toString(16).padStart(2, "0")).join("");
  } };
}

// ../../protocol/tools/strict-json.mjs
var strict_json_exports = {};
__export(strict_json_exports, {
  StrictJSONError: () => StrictJSONError,
  assertInteger: () => assertInteger,
  canonicalize: () => canonicalize,
  hashJSON: () => hashJSON,
  hashOmittingRoot: () => hashOmittingRoot,
  parseJSON: () => parseJSON,
  sha256: () => sha2562
});
var StrictJSONError = class extends Error {
  constructor(code, message, pointer) {
    super(message);
    this.name = "StrictJSONError";
    this.code = code;
    if (pointer !== void 0) this.pointer = pointer;
  }
};
function fail(code, message, pointer) {
  throw new StrictJSONError(code, message, pointer);
}
function assertUnicode(value) {
  for (let i = 0; i < value.length; i++) {
    const unit = value.charCodeAt(i);
    if (unit >= 55296 && unit <= 56319) {
      const next = value.charCodeAt(++i);
      if (!(next >= 56320 && next <= 57343)) {
        fail("JSON_UNICODE", "Unpaired high surrogate");
      }
    } else if (unit >= 56320 && unit <= 57343) {
      fail("JSON_UNICODE", "Unpaired low surrogate");
    }
  }
}
function asBytes(bytes) {
  if (bytes instanceof Uint8Array) return bytes;
  if (bytes instanceof ArrayBuffer) return new Uint8Array(bytes);
  throw new TypeError("Expected UTF-8 bytes (Uint8Array, Buffer, or ArrayBuffer)");
}
var escapePointer = (key2) => key2.replace(/~/g, "~0").replace(/\//g, "~1");
function parseJSON(bytes) {
  const input = asBytes(bytes);
  if (input[0] === 239 && input[1] === 187 && input[2] === 191) {
    fail("JSON_BOM", "Machine JSON must not begin with a UTF-8 BOM");
  }
  let source;
  try {
    source = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(input);
  } catch {
    fail("JSON_UTF8", "Invalid UTF-8");
  }
  let cursor = 0;
  const numbers = /* @__PURE__ */ new Map();
  const syntax = (message) => fail("JSON_SYNTAX", `${message} at UTF-16 offset ${cursor}`);
  const whitespace = () => {
    while (cursor < source.length && /[\x20\x09\x0a\x0d]/.test(source[cursor])) cursor++;
  };
  function string() {
    if (source[cursor++] !== '"') syntax("Expected a string");
    let result = "";
    while (cursor < source.length) {
      const character = source[cursor++];
      if (character === '"') {
        assertUnicode(result);
        return result;
      }
      if (character.charCodeAt(0) < 32) syntax("Unescaped control character");
      if (character !== "\\") {
        result += character;
        continue;
      }
      const escape = source[cursor++];
      const simple = { '"': '"', "\\": "\\", "/": "/", b: "\b", f: "\f", n: "\n", r: "\r", t: "	" };
      if (Object.hasOwn(simple, escape)) {
        result += simple[escape];
      } else if (escape === "u") {
        const hex = source.slice(cursor, cursor + 4);
        if (!/^[0-9a-fA-F]{4}$/.test(hex)) syntax("Invalid Unicode escape");
        result += String.fromCharCode(Number.parseInt(hex, 16));
        cursor += 4;
      } else {
        syntax("Invalid string escape");
      }
    }
    syntax("Unterminated string");
  }
  function value(pointer) {
    whitespace();
    const character = source[cursor];
    if (character === '"') return string();
    if (character === "{") {
      cursor++;
      const result = {};
      const keys = /* @__PURE__ */ new Set();
      whitespace();
      if (source[cursor] === "}") {
        cursor++;
        return result;
      }
      while (true) {
        if (source[cursor] !== '"') syntax("Expected an object key");
        const key2 = string();
        const childPointer = `${pointer}/${escapePointer(key2)}`;
        if (keys.has(key2)) fail("JSON_DUPLICATE_KEY", `Duplicate decoded key ${JSON.stringify(key2)}`, childPointer);
        keys.add(key2);
        whitespace();
        if (source[cursor++] !== ":") syntax("Expected a colon");
        const child = value(childPointer);
        Object.defineProperty(result, key2, { value: child, enumerable: true, writable: true, configurable: true });
        whitespace();
        const separator = source[cursor++];
        if (separator === "}") return result;
        if (separator !== ",") syntax("Expected a comma or closing brace");
        whitespace();
      }
    }
    if (character === "[") {
      cursor++;
      const result = [];
      whitespace();
      if (source[cursor] === "]") {
        cursor++;
        return result;
      }
      while (true) {
        result.push(value(`${pointer}/${result.length}`));
        whitespace();
        const separator = source[cursor++];
        if (separator === "]") return result;
        if (separator !== ",") syntax("Expected a comma or closing bracket");
      }
    }
    for (const [token, literal2] of [["true", true], ["false", false], ["null", null]]) {
      if (source.startsWith(token, cursor)) {
        cursor += token.length;
        return literal2;
      }
    }
    const match = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(source.slice(cursor));
    if (match) {
      const raw = match[0];
      cursor += raw.length;
      const decoded = Number(raw);
      if (!Number.isFinite(decoded)) fail("JSON_NONFINITE", "Number is not finite binary64", pointer);
      numbers.set(pointer, raw);
      return decoded;
    }
    syntax("Expected a JSON value");
  }
  const parsedValue = value("");
  whitespace();
  if (cursor !== source.length) syntax("Trailing content");
  return { value: parsedValue, numbers };
}
function atPointer(value, pointer) {
  if (pointer === "") return value;
  if (typeof pointer !== "string" || !pointer.startsWith("/") || /~(?:[^01]|$)/.test(pointer)) {
    throw new TypeError("Expected an RFC 6901 JSON pointer");
  }
  for (const part of pointer.slice(1).split("/")) {
    const key2 = part.replace(/~1/g, "/").replace(/~0/g, "~");
    if (value === null || typeof value !== "object" || !Object.hasOwn(value, key2)) return void 0;
    value = value[key2];
  }
  return value;
}
function boundedExponent(text, bound) {
  const negative = text.startsWith("-");
  const digits = text.replace(/^[+-]/, "").replace(/^0+/, "") || "0";
  const ceiling = String(bound);
  const absolute = digits.length > ceiling.length || digits.length === ceiling.length && digits > ceiling ? BigInt(bound) + 1n : BigInt(digits);
  return negative ? -absolute : absolute;
}
function assertInteger(parsed, pointer, min = 1, max = 9007199254740991) {
  if (!Number.isSafeInteger(min) || !Number.isSafeInteger(max) || min > max) {
    throw new TypeError("Integer bounds must be ordered safe integers");
  }
  const decoded = atPointer(parsed.value, pointer);
  const raw = parsed.numbers.get(pointer);
  if (typeof decoded !== "number" || typeof raw !== "string") {
    fail("INTEGER_REQUIRED", "Expected an original JSON number token", pointer);
  }
  const match = /^(-?)(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$/.exec(raw);
  if (!match) fail("INTEGER_REQUIRED", "Invalid original JSON number token", pointer);
  const [, sign, whole, fraction = "", exponent = "0"] = match;
  const digits = (whole + fraction).replace(/^0+/, "");
  let exact2;
  if (digits === "") {
    if (sign) fail("INTEGER_NEGATIVE_ZERO", "Negative-zero integer token is prohibited", pointer);
    exact2 = 0n;
  } else {
    const coefficient = digits.replace(/0+$/, "");
    const trailingZeros = digits.length - coefficient.length;
    const shift = boundedExponent(exponent, raw.length + 32) - BigInt(fraction.length) + BigInt(trailingZeros);
    if (shift < 0n) fail("INTEGER_NOT_EXACT", "Original token is not a mathematical integer", pointer);
    if (BigInt(coefficient.length) + shift > 16n) {
      fail("INTEGER_RANGE", `Integer must be within ${min}..${max}`, pointer);
    }
    exact2 = BigInt(sign + coefficient + "0".repeat(Number(shift)));
  }
  if (exact2 < BigInt(min) || exact2 > BigInt(max)) {
    fail("INTEGER_RANGE", `Integer must be within ${min}..${max}`, pointer);
  }
  const result = Number(exact2);
  if (!Object.is(decoded, result)) fail("INTEGER_VALUE_MISMATCH", "Parsed value differs from the validated token", pointer);
  return result;
}
function canonicalize(value) {
  const active = /* @__PURE__ */ new Set();
  function serialize(item) {
    if (item === null || typeof item === "boolean") return JSON.stringify(item);
    if (typeof item === "string") {
      assertUnicode(item);
      return JSON.stringify(item);
    }
    if (typeof item === "number") {
      if (!Number.isFinite(item)) fail("JSON_NONFINITE", "Number is not finite binary64");
      return JSON.stringify(item);
    }
    if (typeof item !== "object") fail("JSON_VALUE", "Value is not a JSON value");
    if (active.has(item)) fail("JSON_CYCLE", "Cyclic value is not JSON");
    active.add(item);
    try {
      if (Array.isArray(item)) {
        const elements = [];
        for (let index = 0; index < item.length; index++) {
          if (!Object.hasOwn(item, index)) fail("JSON_VALUE", "Sparse arrays are not JSON values");
          elements.push(serialize(item[index]));
        }
        return `[${elements.join(",")}]`;
      }
      const prototype = Object.getPrototypeOf(item);
      if (prototype !== Object.prototype && prototype !== null) fail("JSON_VALUE", "Expected a plain JSON object");
      if (Object.getOwnPropertySymbols(item).length) fail("JSON_VALUE", "Symbol keys are not JSON properties");
      const members = Object.keys(item).sort().map((key2) => {
        assertUnicode(key2);
        const descriptor = Object.getOwnPropertyDescriptor(item, key2);
        if (!Object.hasOwn(descriptor, "value")) fail("JSON_VALUE", "Accessors are not JSON values");
        return `${JSON.stringify(key2)}:${serialize(descriptor.value)}`;
      });
      return `{${members.join(",")}}`;
    } finally {
      active.delete(item);
    }
  }
  return serialize(value);
}
function sha2562(bytes) {
  if (typeof bytes === "string") {
    assertUnicode(bytes);
    bytes = Buffer.from(bytes, "utf8");
  }
  return createHash("sha256").update(asBytes(bytes)).digest("hex");
}
function hashJSON(value) {
  return sha2562(Buffer.from(canonicalize(value), "utf8"));
}
function hashOmittingRoot(value, key2) {
  if (value === null || typeof value !== "object" || Array.isArray(value) || typeof key2 !== "string") {
    throw new TypeError("Root omission requires a JSON object and a string key");
  }
  canonicalize(value);
  return hashJSON(Object.fromEntries(Object.entries(value).filter(([name]) => name !== key2)));
}

// ../../protocol/tools/schema-validator.mjs
var keywords = /* @__PURE__ */ new Set(["$schema", "$id", "$defs", "$ref", "title", "description", "$comment", "type", "properties", "required", "const", "enum", "items", "minimum", "maximum", "minItems", "maxItems", "minLength", "maxLength", "pattern", "allOf", "anyOf", "oneOf", "not", "if", "then", "else", "additionalProperties", "uniqueItems"]);
var SchemaError = class extends Error {
  constructor(pointer, rule) {
    super(`${pointer || "/"}: ${rule}`);
    this.code = "SCHEMA";
    this.pointer = pointer;
  }
};
var ptr = (s) => s.replace(/~/g, "~0").replace(/\//g, "~1");
var equal = (a, b) => canonicalize(a) === canonicalize(b);
var object = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
var embeddedSchemas = { "commit.schema.json": { "$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://lifeos.local/protocol/schema/commit.schema.json", "title": "Immutable COMMITTED record C (Machine layer)", "type": "object", "required": ["datasetID", "writerInstanceID", "writerEpoch", "generation", "previousCommitID", "manifestPath", "manifestHash", "committedAt", "takeover", "commitID"], "properties": { "datasetID": { "$ref": "common.schema.json#/$defs/uuid" }, "writerInstanceID": { "$ref": "common.schema.json#/$defs/uuid" }, "writerEpoch": { "$ref": "common.schema.json#/$defs/positiveInteger" }, "generation": { "$ref": "common.schema.json#/$defs/positiveInteger" }, "previousCommitID": { "oneOf": [{ "$ref": "common.schema.json#/$defs/hash" }, { "type": "null" }] }, "manifestPath": { "type": "string", "pattern": "^generations/e[1-9][0-9]*/g[1-9][0-9]*/generation-manifest\\.json$" }, "manifestHash": { "$ref": "common.schema.json#/$defs/hash" }, "committedAt": { "$ref": "common.schema.json#/$defs/instant" }, "takeover": { "oneOf": [{ "$ref": "#/$defs/takeover" }, { "type": "null" }] }, "commitID": { "$ref": "common.schema.json#/$defs/hash" } }, "allOf": [{ "$ref": "common.schema.json#/$defs/noSourceInstanceID" }, { "if": { "properties": { "previousCommitID": { "type": "null" } } }, "then": { "properties": { "writerEpoch": { "const": 1 }, "generation": { "const": 1 }, "takeover": { "type": "null" } } } }], "$defs": { "takeover": { "type": "object", "required": ["previousWriterInstanceID", "reason", "authorizedAt"], "properties": { "previousWriterInstanceID": { "$ref": "common.schema.json#/$defs/uuid" }, "reason": { "$ref": "common.schema.json#/$defs/nonemptyString" }, "authorizedAt": { "$ref": "common.schema.json#/$defs/instant" } }, "allOf": [{ "$ref": "common.schema.json#/$defs/noSourceInstanceID" }] }, "current": { "title": "Discovery hint only; never publication authority", "type": "object", "required": ["commitID"], "properties": { "commitID": { "$ref": "common.schema.json#/$defs/hash" } }, "allOf": [{ "$ref": "common.schema.json#/$defs/noSourceInstanceID" }] } } }, "common.schema.json": { "$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://lifeos.local/protocol/schema/common.schema.json", "title": "LifeOS shared wire primitives", "$defs": { "uuid": { "type": "string", "pattern": "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" }, "hash": { "type": "string", "pattern": "^[0-9a-f]{64}$" }, "positiveInteger": { "type": "integer", "minimum": 1, "maximum": 9007199254740991 }, "nonnegativeInteger": { "type": "integer", "minimum": 0, "maximum": 9007199254740991 }, "schemaVersion": { "type": "object", "required": ["major", "minor"], "properties": { "major": { "$ref": "#/$defs/positiveInteger" }, "minor": { "$ref": "#/$defs/nonnegativeInteger" } } }, "instant": { "type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$" }, "dayKey": { "type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}$" }, "timeZone": { "type": "string", "pattern": "^[A-Za-z0-9_+.-]+(?:/[A-Za-z0-9_+.-]+)*$" }, "entityType": { "type": "string", "enum": ["Goal", "Project", "Task", "DraftPlan", "CalendarCommitment", "ActualSession", "DailyReview"] }, "nonemptyString": { "type": "string", "pattern": "[\\s\\S]" }, "noSourceInstanceID": { "not": { "required": ["sourceInstanceID"] } }, "relativePath": { "type": "string", "pattern": "^(?!/)(?![\\s\\S]*[\\\\:\\u0000-\\u001f\\u007f])(?![\\s\\S]*(?:^|/)(?:\\.|\\.\\.)(?:/|$))(?![\\s\\S]*//)(?![\\s\\S]*[ .](?:/|$))[^/]+(?:/[^/]+)*$" }, "dayRange": { "type": "object", "required": ["startDayKey", "endDayKeyExclusive"], "properties": { "startDayKey": { "$ref": "#/$defs/dayKey" }, "endDayKeyExclusive": { "$ref": "#/$defs/dayKey" } }, "allOf": [{ "$ref": "#/$defs/noSourceInstanceID" }] }, "scope": { "type": "object", "required": ["datasetID", "entityTypes", "dayRange"], "properties": { "datasetID": { "$ref": "#/$defs/uuid" }, "entityTypes": { "type": "array", "items": { "$ref": "#/$defs/entityType" } }, "dayRange": { "$ref": "#/$defs/dayRange" } }, "allOf": [{ "$ref": "#/$defs/noSourceInstanceID" }] } } }, "entity.schema.json": { "$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://lifeos.local/protocol/schema/entity.schema.json", "title": "LifeOS minimal frozen entity contract (Machine layer)", "type": "object", "required": ["datasetID", "entityType", "entityID", "revision", "contentHash"], "properties": { "datasetID": { "$ref": "common.schema.json#/$defs/uuid" }, "entityType": { "$ref": "common.schema.json#/$defs/entityType" }, "entityID": { "$ref": "common.schema.json#/$defs/uuid" }, "revision": { "$ref": "common.schema.json#/$defs/positiveInteger" }, "contentHash": { "$ref": "common.schema.json#/$defs/hash" }, "source": { "$ref": "common.schema.json#/$defs/nonemptyString" }, "taskID": { "oneOf": [{ "$ref": "common.schema.json#/$defs/uuid" }, { "type": "null" }] }, "projectID": { "oneOf": [{ "$ref": "common.schema.json#/$defs/uuid" }, { "type": "null" }] }, "goalID": { "oneOf": [{ "$ref": "common.schema.json#/$defs/uuid" }, { "type": "null" }] } }, "allOf": [{ "$ref": "common.schema.json#/$defs/noSourceInstanceID" }, { "not": { "required": ["relationIDs"] } }, { "if": { "properties": { "entityType": { "const": "Task" } } }, "then": { "required": ["lifecycleStatus"], "properties": { "lifecycleStatus": { "enum": ["open", "completed", "cancelled", "archived"] } } } }, { "if": { "properties": { "entityType": { "const": "DraftPlan" } } }, "then": { "required": ["lifecycleStatus", "plannedStart", "plannedEnd", "attributionTimeZone"], "properties": { "lifecycleStatus": { "enum": ["active", "cancelled", "archived"] }, "plannedStart": { "$ref": "common.schema.json#/$defs/instant" }, "plannedEnd": { "$ref": "common.schema.json#/$defs/instant" }, "isFlexible": { "type": "boolean" }, "attributionTimeZone": { "$ref": "common.schema.json#/$defs/timeZone" } } } }, { "if": { "properties": { "entityType": { "const": "CalendarCommitment" } } }, "then": { "required": ["lifecycleStatus", "allDay"], "properties": { "lifecycleStatus": { "enum": ["active", "cancelled"] }, "allDay": { "type": "boolean" }, "availability": { "$ref": "common.schema.json#/$defs/nonemptyString" }, "isReadOnly": { "type": "boolean" }, "calendarLabel": { "type": "string" } }, "allOf": [{ "if": { "properties": { "allDay": { "const": true } } }, "then": { "required": ["localStartDate", "localEndDateExclusive", "calendarTimeZone"], "properties": { "localStartDate": { "$ref": "common.schema.json#/$defs/dayKey" }, "localEndDateExclusive": { "$ref": "common.schema.json#/$defs/dayKey" }, "calendarTimeZone": { "$ref": "common.schema.json#/$defs/timeZone" } }, "allOf": [{ "not": { "required": ["start"] } }, { "not": { "required": ["end"] } }] } }, { "if": { "properties": { "allDay": { "const": false } } }, "then": { "required": ["start", "end", "attributionTimeZone"], "properties": { "start": { "$ref": "common.schema.json#/$defs/instant" }, "end": { "$ref": "common.schema.json#/$defs/instant" }, "attributionTimeZone": { "$ref": "common.schema.json#/$defs/timeZone" } } } }] } }, { "if": { "properties": { "entityType": { "const": "ActualSession" } } }, "then": { "required": ["runState", "factState", "actualStart", "actualEnd", "attributionTimeZone"], "properties": { "runState": { "enum": ["running", "stopped"] }, "factState": { "enum": ["inferred", "confirmed", "rejected"] }, "actualStart": { "$ref": "common.schema.json#/$defs/instant" }, "actualEnd": { "oneOf": [{ "$ref": "common.schema.json#/$defs/instant" }, { "type": "null" }] }, "sourceKind": { "$ref": "common.schema.json#/$defs/nonemptyString" }, "attributionTimeZone": { "$ref": "common.schema.json#/$defs/timeZone" }, "primaryDraftPlanID": { "oneOf": [{ "$ref": "common.schema.json#/$defs/uuid" }, { "type": "null" }] } }, "allOf": [{ "not": { "required": ["draftPlanID"] } }, { "if": { "properties": { "runState": { "const": "running" } } }, "then": { "properties": { "actualEnd": { "type": "null" } } } }, { "if": { "properties": { "runState": { "const": "stopped" } } }, "then": { "properties": { "actualEnd": { "$ref": "common.schema.json#/$defs/instant" } } } }] } }, { "if": { "properties": { "entityType": { "const": "DailyReview" } } }, "then": { "required": ["dayKey"], "properties": { "dayKey": { "$ref": "common.schema.json#/$defs/dayKey" } } } }], "$defs": { "tombstone": { "type": "object", "required": ["datasetID", "entityType", "entityID", "revision", "contentHash"], "properties": { "datasetID": { "$ref": "common.schema.json#/$defs/uuid" }, "entityType": { "$ref": "common.schema.json#/$defs/entityType" }, "entityID": { "$ref": "common.schema.json#/$defs/uuid" }, "revision": { "$ref": "common.schema.json#/$defs/positiveInteger" }, "contentHash": { "$ref": "common.schema.json#/$defs/hash" } }, "allOf": [{ "$ref": "common.schema.json#/$defs/noSourceInstanceID" }] } } }, "intent.schema.json": { "$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://lifeos.local/protocol/schema/intent.schema.json", "title": "Append-only controlled intent (operation layer; Slice 4 onward)", "type": "object", "required": ["operationID", "clientInstanceID", "datasetID", "intentSchemaVersion", "type", "createdAt", "expiresAt", "capabilityVersion", "payload", "payloadHash"], "properties": { "operationID": { "$ref": "common.schema.json#/$defs/uuid" }, "clientInstanceID": { "$ref": "common.schema.json#/$defs/uuid" }, "datasetID": { "$ref": "common.schema.json#/$defs/uuid" }, "intentSchemaVersion": { "$ref": "common.schema.json#/$defs/schemaVersion" }, "type": { "enum": ["DailyReviewDraft", "CancelIntent"] }, "createdAt": { "$ref": "common.schema.json#/$defs/instant" }, "expiresAt": { "$ref": "common.schema.json#/$defs/instant" }, "capabilityVersion": { "$ref": "common.schema.json#/$defs/schemaVersion" }, "payload": { "type": "object" }, "payloadHash": { "$ref": "common.schema.json#/$defs/hash" } }, "allOf": [{ "$ref": "common.schema.json#/$defs/noSourceInstanceID" }, { "if": { "properties": { "type": { "const": "DailyReviewDraft" } } }, "then": { "properties": { "payload": { "required": ["dayKey"], "properties": { "dayKey": { "$ref": "common.schema.json#/$defs/dayKey" } } } } } }, { "if": { "properties": { "type": { "const": "CancelIntent" } } }, "then": { "properties": { "payload": { "required": ["targetOperationID"], "properties": { "targetOperationID": { "$ref": "common.schema.json#/$defs/uuid" } } } } } }] }, "manifest.schema.json": { "$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://lifeos.local/protocol/schema/manifest.schema.json", "title": "Generation manifest M (Machine layer)", "type": "object", "required": ["schemaVersion", "datasetID", "writerInstanceID", "writerEpoch", "generation", "isCompleteSnapshot", "scope", "requiredCapabilities", "capabilities", "machineTransportMode", "entries"], "properties": { "schemaVersion": { "$ref": "common.schema.json#/$defs/schemaVersion" }, "datasetID": { "$ref": "common.schema.json#/$defs/uuid" }, "writerInstanceID": { "$ref": "common.schema.json#/$defs/uuid" }, "writerEpoch": { "$ref": "common.schema.json#/$defs/positiveInteger" }, "generation": { "$ref": "common.schema.json#/$defs/positiveInteger" }, "isCompleteSnapshot": { "const": true }, "scope": { "$ref": "common.schema.json#/$defs/scope" }, "requiredCapabilities": { "type": "array", "items": { "$ref": "common.schema.json#/$defs/nonemptyString" } }, "capabilities": { "type": "object", "required": ["defaultIntentTTLSeconds", "maxIntentTTLSeconds"], "properties": { "defaultIntentTTLSeconds": { "type": "integer", "minimum": 2592e3, "maximum": 2592e3, "const": 2592e3 }, "maxIntentTTLSeconds": { "type": "integer", "minimum": 2592e3, "maximum": 2592e3, "const": 2592e3 } } }, "machineTransportMode": { "enum": ["vault-file", "manual-bundle", "bridge", "unsupported"] }, "projection": { "description": "Hash any complete JSON value at Machine layer; validate #/$defs/projectionConfiguration separately at Projection layer." }, "entries": { "type": "array", "items": { "$ref": "#/$defs/entry" } } }, "allOf": [{ "$ref": "common.schema.json#/$defs/noSourceInstanceID" }, { "not": { "required": ["contentHash"] } }, { "not": { "required": ["manifestHash"] } }, { "not": { "required": ["commitID"] } }], "$defs": { "entry": { "type": "object", "required": ["kind", "contentHash"], "properties": { "kind": { "enum": ["snapshot", "day", "projection"] }, "contentHash": { "$ref": "common.schema.json#/$defs/hash" } }, "allOf": [{ "$ref": "common.schema.json#/$defs/noSourceInstanceID" }, { "not": { "required": ["contentPath"] } }, { "if": { "properties": { "kind": { "const": "day" } } }, "then": { "required": ["dayKey"], "properties": { "dayKey": { "$ref": "common.schema.json#/$defs/dayKey" } } } }, { "if": { "properties": { "kind": { "const": "projection" } } }, "then": { "required": ["projectionKey"], "properties": { "projectionKey": { "$ref": "common.schema.json#/$defs/hash" } } } }] }, "projectionConfiguration": { "type": "object", "required": ["vaultBindingID", "projectionWriterMode", "projectionWriterEpoch", "projectionWriterInstanceID", "projectionSchemaVersion", "projectionRootRelativePath", "dailyNotePathPattern", "dailyNotePathPatternVersion"], "properties": { "vaultBindingID": { "$ref": "common.schema.json#/$defs/uuid" }, "projectionWriterMode": { "enum": ["direct", "delegated", "disabled"] }, "projectionWriterEpoch": { "$ref": "common.schema.json#/$defs/positiveInteger" }, "projectionWriterInstanceID": { "oneOf": [{ "$ref": "common.schema.json#/$defs/uuid" }, { "type": "null" }] }, "projectionSchemaVersion": { "$ref": "common.schema.json#/$defs/schemaVersion" }, "projectionRootRelativePath": { "$ref": "common.schema.json#/$defs/relativePath" }, "dailyNotePathPattern": { "$ref": "common.schema.json#/$defs/relativePath" }, "dailyNotePathPatternVersion": { "$ref": "common.schema.json#/$defs/positiveInteger" } }, "allOf": [{ "$ref": "common.schema.json#/$defs/noSourceInstanceID" }, { "if": { "properties": { "projectionWriterMode": { "const": "disabled" } } }, "then": { "properties": { "projectionWriterInstanceID": { "type": "null" } } } }, { "if": { "properties": { "projectionWriterMode": { "enum": ["direct", "delegated"] } } }, "then": { "properties": { "projectionWriterInstanceID": { "$ref": "common.schema.json#/$defs/uuid" } } } }] } } }, "projection.schema.json": { "$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://lifeos.local/protocol/schema/projection.schema.json", "title": "ProjectionInstructionPayload P (Projection layer only)", "description": "Apply only after Machine integrity passes and facts can promote. Failure blocks this projection, not the generation. No BoundProjectionInstruction wire representation exists.", "type": "object", "required": ["datasetID", "vaultBindingID", "projectionSchemaVersion", "projectionKey", "dayKey", "blockRole", "blockID", "blockOwner", "renderedMarkdown", "renderedContentHash", "createIfMissing", "contentHash"], "properties": { "datasetID": { "$ref": "common.schema.json#/$defs/uuid" }, "vaultBindingID": { "$ref": "common.schema.json#/$defs/uuid" }, "projectionSchemaVersion": { "$ref": "common.schema.json#/$defs/schemaVersion" }, "projectionKey": { "$ref": "common.schema.json#/$defs/hash" }, "dayKey": { "$ref": "common.schema.json#/$defs/dayKey" }, "blockRole": { "type": "string", "pattern": "^[a-z][a-z0-9-]*$" }, "blockID": { "$ref": "common.schema.json#/$defs/hash" }, "blockOwner": { "const": "lifeos" }, "renderedMarkdown": { "type": "string", "pattern": "^[^\\r]*$" }, "renderedContentHash": { "$ref": "common.schema.json#/$defs/hash" }, "createIfMissing": { "type": "boolean" }, "expectedPreviousBlockHash": { "$ref": "common.schema.json#/$defs/hash" }, "contentHash": { "$ref": "common.schema.json#/$defs/hash" } }, "allOf": [{ "$ref": "common.schema.json#/$defs/noSourceInstanceID" }, { "not": { "required": ["sourceCommitID"] } }, { "not": { "required": ["targetRelativeNotePath"] } }, { "not": { "required": ["targetPath"] } }, { "not": { "required": ["startMarker"] } }, { "not": { "required": ["endMarker"] } }] }, "receipt.schema.json": { "$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://lifeos.local/protocol/schema/receipt.schema.json", "title": "Immutable receipt event (operation layer)", "type": "object", "required": ["operationID", "receiptSequence", "status", "emittedAt", "payloadHash", "previousReceiptHash", "receiptHash"], "properties": { "operationID": { "$ref": "common.schema.json#/$defs/uuid" }, "receiptSequence": { "$ref": "common.schema.json#/$defs/positiveInteger" }, "status": { "enum": ["received", "accepted", "rejected", "expired", "cancelled"] }, "emittedAt": { "$ref": "common.schema.json#/$defs/instant" }, "payloadHash": { "$ref": "common.schema.json#/$defs/hash" }, "previousReceiptHash": { "oneOf": [{ "$ref": "common.schema.json#/$defs/hash" }, { "type": "null" }] }, "receiptHash": { "$ref": "common.schema.json#/$defs/hash" }, "finalEntityID": { "$ref": "common.schema.json#/$defs/uuid" }, "entityRevision": { "$ref": "common.schema.json#/$defs/positiveInteger" }, "errorCode": { "$ref": "common.schema.json#/$defs/nonemptyString" }, "reason": { "$ref": "common.schema.json#/$defs/nonemptyString" } }, "allOf": [{ "$ref": "common.schema.json#/$defs/noSourceInstanceID" }, { "if": { "properties": { "receiptSequence": { "const": 1 } } }, "then": { "properties": { "previousReceiptHash": { "type": "null" } } } }, { "if": { "properties": { "receiptSequence": { "minimum": 2 } } }, "then": { "properties": { "previousReceiptHash": { "$ref": "common.schema.json#/$defs/hash" } } } }, { "if": { "properties": { "status": { "const": "received" } } }, "then": { "properties": { "receiptSequence": { "const": 1 } } } }, { "if": { "properties": { "status": { "enum": ["rejected", "expired", "cancelled"] } } }, "then": { "required": ["errorCode", "reason"] } }, { "if": { "required": ["finalEntityID"] }, "then": { "required": ["entityRevision"], "properties": { "status": { "const": "accepted" } } } }, { "if": { "required": ["entityRevision"] }, "then": { "required": ["finalEntityID"], "properties": { "status": { "const": "accepted" } } } }] }, "segment.schema.json": { "$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://lifeos.local/protocol/schema/segment.schema.json", "title": "ActualSession daily segment (Machine layer; derived, not an entity)", "type": "object", "required": ["sessionID", "dayKey", "start", "end", "entityRevision", "index", "provisional"], "properties": { "sessionID": { "$ref": "common.schema.json#/$defs/uuid" }, "dayKey": { "$ref": "common.schema.json#/$defs/dayKey" }, "start": { "$ref": "common.schema.json#/$defs/instant" }, "end": { "$ref": "common.schema.json#/$defs/instant" }, "entityRevision": { "$ref": "common.schema.json#/$defs/positiveInteger" }, "index": { "$ref": "common.schema.json#/$defs/nonnegativeInteger" }, "provisional": { "type": "boolean" } }, "allOf": [{ "$ref": "common.schema.json#/$defs/noSourceInstanceID" }], "$defs": { "dayPackage": { "type": "object", "required": ["schemaVersion", "datasetID", "dayKey", "segments", "contentHash"], "properties": { "schemaVersion": { "$ref": "common.schema.json#/$defs/schemaVersion" }, "datasetID": { "$ref": "common.schema.json#/$defs/uuid" }, "dayKey": { "$ref": "common.schema.json#/$defs/dayKey" }, "segments": { "type": "array", "items": { "$ref": "#" } }, "contentHash": { "$ref": "common.schema.json#/$defs/hash" } }, "allOf": [{ "$ref": "common.schema.json#/$defs/noSourceInstanceID" }] } } }, "snapshot.schema.json": { "$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://lifeos.local/protocol/schema/snapshot.schema.json", "title": "Self-contained materialized snapshot (Machine layer)", "type": "object", "required": ["schemaVersion", "datasetID", "isCompleteSnapshot", "scope", "entities", "tombstones", "contentHash"], "properties": { "schemaVersion": { "$ref": "common.schema.json#/$defs/schemaVersion" }, "datasetID": { "$ref": "common.schema.json#/$defs/uuid" }, "isCompleteSnapshot": { "const": true }, "scope": { "$ref": "common.schema.json#/$defs/scope" }, "entities": { "type": "array", "items": { "$ref": "entity.schema.json" } }, "tombstones": { "type": "array", "items": { "$ref": "entity.schema.json#/$defs/tombstone" } }, "contentHash": { "$ref": "common.schema.json#/$defs/hash" } }, "allOf": [{ "$ref": "common.schema.json#/$defs/noSourceInstanceID" }] } };
function load(file) {
  if (!Object.hasOwn(embeddedSchemas, file)) throw Error("Nonlocal schema reference");
  return embeddedSchemas[file];
}
function resolve(ref, file) {
  const [name, fragment = ""] = ref.split("#");
  const target = name || file;
  let schema = load(target);
  if (fragment && !fragment.startsWith("/")) throw new Error("Invalid schema fragment");
  if (fragment) for (const encoded of fragment.slice(1).split("/")) {
    const key2 = encoded.replace(/~1/g, "/").replace(/~0/g, "~");
    if (!schema || !Object.hasOwn(schema, key2)) throw new Error(`Missing schema ${ref}`);
    schema = schema[key2];
  }
  if (!schema) throw new Error(`Missing schema ${ref}`);
  return [schema, target];
}
function validateSchema(parsed, name, fragment = "", pointer = "") {
  const [schema, file] = resolve(name + (fragment ? "#" + fragment : ""), name);
  function walk(v, s, f, p) {
    if (typeof s === "boolean") {
      if (!s) throw new SchemaError(p, "false");
      return;
    }
    for (const key2 of Object.keys(s)) if (!keywords.has(key2)) throw new Error(`Unsupported schema keyword ${key2}`);
    const fail4 = (r) => {
      throw new SchemaError(p, r);
    };
    const matches = (sub) => {
      try {
        walk(v, sub, f, p);
        return true;
      } catch (e) {
        if (e instanceof SchemaError || e.code?.startsWith("INTEGER_")) return false;
        throw e;
      }
    };
    if (s.$ref) {
      const [r, rf] = resolve(s.$ref, f);
      walk(v, r, rf, p);
    }
    if (s.type) {
      const kinds = Array.isArray(s.type) ? s.type : [s.type];
      if (!kinds.some((t) => t === "object" ? object(v) : t === "array" ? Array.isArray(v) : t === "null" ? v === null : t === "integer" ? typeof v === "number" && Number.isInteger(v) : t === "number" ? typeof v === "number" : typeof v === t)) fail4("type");
      if (kinds.includes("integer") && typeof v === "number") assertInteger(parsed, p, s.minimum ?? -9007199254740991, s.maximum ?? 9007199254740991);
    }
    if (s.const !== void 0 && !equal(v, s.const)) fail4("const");
    if (s.enum && !s.enum.some((x) => equal(v, x))) fail4("enum");
    if (typeof v === "number" && (s.minimum !== void 0 && v < s.minimum || s.maximum !== void 0 && v > s.maximum)) fail4("range");
    if (typeof v === "string") {
      if (s.minLength !== void 0 && [...v].length < s.minLength || s.maxLength !== void 0 && [...v].length > s.maxLength) fail4("length");
      if (s.pattern && !new RegExp(s.pattern, "u").test(v)) fail4("pattern");
    }
    if (object(v)) {
      for (const key2 of s.required ?? []) if (!Object.hasOwn(v, key2)) fail4(`required ${key2}`);
      for (const [key2, sub] of Object.entries(s.properties ?? {})) if (Object.hasOwn(v, key2)) walk(v[key2], sub, f, p + "/" + ptr(key2));
      if (s.additionalProperties === false) {
        for (const key2 of Object.keys(v)) if (!Object.hasOwn(s.properties ?? {}, key2)) fail4(`additional ${key2}`);
      }
    }
    if (Array.isArray(v)) {
      if (s.minItems !== void 0 && v.length < s.minItems || s.maxItems !== void 0 && v.length > s.maxItems) fail4("items length");
      if (s.uniqueItems && new Set(v.map(canonicalize)).size !== v.length) fail4("uniqueItems");
      if (s.items) v.forEach((item, i) => walk(item, s.items, f, p + "/" + i));
    }
    for (const sub of s.allOf ?? []) walk(v, sub, f, p);
    if (s.anyOf && !s.anyOf.some(matches)) fail4("anyOf");
    if (s.oneOf && s.oneOf.filter(matches).length !== 1) fail4("oneOf");
    if (s.not && matches(s.not)) fail4("not");
    if (s.if) {
      const branch = matches(s.if) ? s.then : s.else;
      if (branch) walk(v, branch, f, p);
    }
  }
  let value = parsed.value;
  if (pointer) for (const key2 of pointer.slice(1).split("/")) value = value[key2.replace(/~1/g, "/").replace(/~0/g, "~")];
  walk(value, schema, file, pointer);
  return value;
}

// ../../protocol/tools/protocol.mjs
var protocol_exports = {};
__export(protocol_exports, {
  ProtocolError: () => ProtocolError,
  bindProjection: () => bindProjection,
  commitPath: () => commitPath,
  generationRoot: () => generationRoot,
  manifestPath: () => manifestPath,
  memberPath: () => memberPath,
  relativePath: () => relativePath,
  selectHead: () => selectHead,
  splitSession: () => splitSession,
  validDay: () => validDay,
  validInstant: () => validInstant,
  validateGeneration: () => validateGeneration
});
var ProtocolError = class extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
};
var fail2 = (code) => {
  throw new ProtocolError(code);
};
var same = (a, b) => canonicalize(a) === canonicalize(b);
var digest = (v, key2 = "contentHash") => {
  if (v[key2] !== hashOmittingRoot(v, key2)) fail2("MACHINE_HASH");
};
var deepFreeze = (v) => {
  if (v && typeof v === "object" && !Object.isFrozen(v)) {
    Object.values(v).forEach(deepFreeze);
    Object.freeze(v);
  }
  return v;
};
var DAY = 864e5;
function validDay(day) {
  return /^\d{4}-\d{2}-\d{2}$/.test(day) && Number.isFinite(Date.parse(day + "T00:00:00.000Z")) && (/* @__PURE__ */ new Date(day + "T00:00:00.000Z")).toISOString().slice(0, 10) === day;
}
function validInstant(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) && Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value;
}
function relativePath(p, { ascii = false } = {}) {
  if (typeof p !== "string" || !p || /[\\:\x00-\x1f\x7f]/.test(p) || p.split("/").some((s) => !s || s === "." || s === "..") || ascii && !/^[a-z0-9./-]+$/.test(p)) fail2("MACHINE_PATH");
  return p;
}
var generationRoot = (c) => `generations/e${c.writerEpoch}/g${c.generation}`;
var manifestPath = (c) => `${generationRoot(c)}/generation-manifest.json`;
var commitPath = (c) => `commits/e${c.writerEpoch}-g${c.generation}-${c.commitID}.json`;
function memberPath(e) {
  if (e.kind === "snapshot") return "snapshot.json";
  if (e.kind === "day" && validDay(e.dayKey)) return `days/${e.dayKey}.json`;
  if (e.kind === "projection" && /^[0-9a-f]{64}$/.test(e.projectionKey)) return `projections/${e.projectionKey}.json`;
  fail2("MACHINE_PATH");
}
function selectHead(commitBytes, datasetID) {
  const nodes = /* @__PURE__ */ new Map(), positions = /* @__PURE__ */ new Map();
  for (const bytes of commitBytes) {
    const p = parseJSON(bytes);
    const c = validateSchema(p, "commit.schema.json");
    digest(c, "commitID");
    if (c.datasetID !== datasetID) fail2("LEDGER_DATASET");
    if (c.manifestPath !== manifestPath(c)) fail2("MACHINE_PATH");
    if (!validInstant(c.committedAt)) fail2("LEDGER_TIME");
    if (nodes.has(c.commitID) && !same(nodes.get(c.commitID), c)) fail2("LEDGER_FORK");
    const position = `${c.writerEpoch}:${c.generation}`;
    if (positions.has(position) && positions.get(position) !== c.commitID) fail2("LEDGER_FORK");
    positions.set(position, c.commitID);
    nodes.set(c.commitID, c);
  }
  const roots = [...nodes.values()].filter((c) => c.previousCommitID === null);
  if (roots.length !== 1) fail2("LEDGER_ROOT");
  const children = /* @__PURE__ */ new Map();
  for (const c of nodes.values()) {
    if (c.previousCommitID === null) {
      if (c.writerEpoch !== 1 || c.generation !== 1 || c.takeover !== null) fail2("LEDGER_ROOT");
      continue;
    }
    const p = nodes.get(c.previousCommitID);
    if (!p) fail2("LEDGER_GAP");
    if (c.takeover !== null) {
      if (c.writerEpoch !== p.writerEpoch + 1 || c.generation !== 1 || c.takeover.previousWriterInstanceID !== p.writerInstanceID || !validInstant(c.takeover.authorizedAt)) fail2("LEDGER_TAKEOVER");
    } else if (c.writerEpoch !== p.writerEpoch || c.generation !== p.generation + 1 || c.writerInstanceID !== p.writerInstanceID) fail2("LEDGER_SUCCESSION");
    if (!children.has(p.commitID)) children.set(p.commitID, []);
    children.get(p.commitID).push(c);
  }
  const ancestry = [];
  let head = roots[0];
  const stale = [];
  for (; ; ) {
    ancestry.push(head.commitID);
    const next = children.get(head.commitID) ?? [];
    if (!next.length) break;
    const takeovers = next.filter((c) => c.takeover !== null);
    if (takeovers.length > 1 || !takeovers.length && next.length > 1) fail2("LEDGER_FORK");
    if (takeovers.length) {
      const pending = next.filter((c) => c.takeover === null);
      while (pending.length) {
        const old = pending.pop();
        stale.push(old.commitID);
        pending.push(...children.get(old.commitID) ?? []);
      }
      head = takeovers[0];
    } else head = next[0];
  }
  return { head, nodes, ancestry, stale };
}
function dayInZone(ms, zone) {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date(ms));
  const o = Object.fromEntries(parts.map((x) => [x.type, x.value]));
  return `${o.year}-${o.month}-${o.day}`;
}
function splitSession(session, asOf) {
  const stop = session.actualEnd ?? asOf;
  if (!validInstant(session.actualStart) || !validInstant(stop)) fail2("MACHINE_TIME");
  let cursor = Date.parse(session.actualStart), end = Date.parse(stop);
  if (end <= cursor) fail2("MACHINE_TIME");
  let index = 0;
  const segments = [];
  while (cursor < end) {
    const day = dayInZone(cursor, session.attributionTimeZone);
    let boundary = end;
    if (dayInZone(end - 1, session.attributionTimeZone) !== day) {
      let lo = cursor + 1, hi = Math.min(end, cursor + 2 * DAY);
      while (lo < hi) {
        const mid = Math.floor((lo + hi) / 2);
        if (dayInZone(mid, session.attributionTimeZone) === day) lo = mid + 1;
        else hi = mid;
      }
      boundary = lo;
    }
    segments.push({ sessionID: session.entityID, dayKey: day, start: new Date(cursor).toISOString(), end: new Date(boundary).toISOString(), entityRevision: session.revision, index: index++, provisional: session.runState === "running" });
    cursor = boundary;
  }
  return segments;
}
function verifySnapshot(snapshot, manifest, days, previous, committedAt) {
  if (snapshot.datasetID !== manifest.datasetID || !same(snapshot.scope, manifest.scope) || manifest.scope.datasetID !== manifest.datasetID) fail2("MACHINE_SCOPE");
  const { startDayKey, endDayKeyExclusive } = manifest.scope.dayRange;
  if (!validDay(startDayKey) || !validDay(endDayKeyExclusive) || startDayKey >= endDayKeyExclusive) fail2("MACHINE_SCOPE");
  const expectedDays = [];
  for (let t = Date.parse(startDayKey); t < Date.parse(endDayKeyExclusive); t += DAY) expectedDays.push(new Date(t).toISOString().slice(0, 10));
  if (!same([...days.keys()].sort(), expectedDays)) fail2("MACHINE_DAY_COVERAGE");
  const ids = /* @__PURE__ */ new Map(), reviews = /* @__PURE__ */ new Set();
  const oldEntities = new Map([...previous?.entities ?? [], ...previous?.tombstones ?? []].map((e) => [e.entityType + ":" + e.entityID, e]));
  const oldTombstones = new Set((previous?.tombstones ?? []).map((e) => e.entityType + ":" + e.entityID));
  const newTombstones = new Set(snapshot.tombstones.map((e) => e.entityType + ":" + e.entityID));
  for (const key3 of oldTombstones) {
    if (snapshot.entities.some((e) => e.entityType + ":" + e.entityID === key3)) fail2("MACHINE_TOMBSTONE_RESURRECTION");
    if (!newTombstones.has(key3)) fail2("MACHINE_TOMBSTONE_GC");
  }
  for (const [list, tombstone] of [[snapshot.entities, false], [snapshot.tombstones, true]]) for (const e of list) {
    digest(e);
    if (e.datasetID !== manifest.datasetID || !tombstone && !manifest.scope.entityTypes.includes(e.entityType)) fail2("MACHINE_IDENTITY");
    const key3 = e.entityType + ":" + e.entityID;
    if (ids.has(key3)) fail2("MACHINE_REVISION_CONFLICT");
    ids.set(key3, e);
    const old = oldEntities.get(key3);
    if (old && (e.revision < old.revision || e.revision === old.revision && e.contentHash !== old.contentHash)) fail2("MACHINE_REVISION_CONFLICT");
    if (tombstone && old && (previous.entities ?? []).includes(old) && e.revision <= old.revision) fail2("MACHINE_TOMBSTONE");
    if (tombstone) continue;
    if (e.entityType === "DailyReview") {
      if (reviews.has(e.dayKey)) fail2("MACHINE_REVIEW_DUPLICATE");
      reviews.add(e.dayKey);
      if (!validDay(e.dayKey)) fail2("MACHINE_TIME");
    }
    const interval = e.entityType === "DraftPlan" ? [e.plannedStart, e.plannedEnd] : e.entityType === "CalendarCommitment" && !e.allDay ? [e.start, e.end] : e.entityType === "ActualSession" ? [e.actualStart, e.actualEnd] : null;
    if (interval && (!validInstant(interval[0]) || interval[1] !== null && (!validInstant(interval[1]) || interval[0] >= interval[1]))) fail2("MACHINE_TIME");
    if (e.entityType === "CalendarCommitment" && e.allDay && (!validDay(e.localStartDate) || !validDay(e.localEndDateExclusive) || e.localStartDate >= e.localEndDateExclusive)) fail2("MACHINE_TIME");
    for (const z of [e.attributionTimeZone, e.calendarTimeZone].filter(Boolean)) try {
      dayInZone(0, z);
    } catch {
      fail2("MACHINE_TIMEZONE");
    }
  }
  const actual = [];
  for (const [day, pkg] of days) {
    if (pkg.datasetID !== manifest.datasetID || pkg.dayKey !== day) fail2("MACHINE_DAY_IDENTITY");
    for (const s of pkg.segments) {
      if (s.dayKey !== day) fail2("MACHINE_SEGMENT");
      actual.push(s);
    }
  }
  const expected = [];
  for (const e of snapshot.entities.filter((e2) => e2.entityType === "ActualSession")) {
    const supplied = actual.filter((s) => s.sessionID === e.entityID);
    const asOf = supplied.map((s) => s.end).sort().at(-1);
    if (e.runState === "running") {
      if (e.actualStart > committedAt || asOf && asOf > committedAt) fail2("MACHINE_RUNNING_HORIZON");
      if (!asOf) {
        const intersects = e.actualStart < committedAt && splitSession(e, committedAt).some((s) => s.dayKey >= startDayKey && s.dayKey < endDayKeyExclusive);
        if (intersects) fail2("MACHINE_SEGMENT_MISSING");
        continue;
      }
    }
    for (const s of splitSession(e, asOf)) if (s.dayKey >= startDayKey && s.dayKey < endDayKeyExclusive) expected.push(s);
  }
  const key2 = (s) => s.sessionID + ":" + String(s.index).padStart(16, "0");
  const semantic = (s) => Object.fromEntries(["sessionID", "dayKey", "start", "end", "entityRevision", "index", "provisional"].map((k) => [k, s[k]]));
  if (!same(actual.map(semantic).sort((a, b) => key2(a).localeCompare(key2(b))), expected.sort((a, b) => key2(a).localeCompare(key2(b))))) fail2("MACHINE_SEGMENT");
  return snapshot;
}
var verifiedHandles = /* @__PURE__ */ new WeakMap();
var factSummary = (e) => Object.fromEntries(["datasetID", "entityType", "entityID", "revision", "contentHash"].map((k) => [k, e[k]]));
function retainFacts(snapshot, previous) {
  const live = new Map((previous?.entities ?? []).map((e) => [e.entityType + ":" + e.entityID, e]));
  const deleted = new Map((previous?.tombstones ?? []).map((e) => [e.entityType + ":" + e.entityID, e]));
  for (const e of snapshot.entities) live.set(e.entityType + ":" + e.entityID, factSummary(e));
  for (const e of snapshot.tombstones) {
    const key2 = e.entityType + ":" + e.entityID;
    live.delete(key2);
    deleted.set(key2, factSummary(e));
  }
  return deepFreeze({ entities: [...live.values()], tombstones: [...deleted.values()] });
}
function projectionHistory(ledger, files, currentManifest, previousInternal, supportedCapabilities) {
  const history = /* @__PURE__ */ new Map();
  let bindings = /* @__PURE__ */ new Map(), gap = false;
  for (const commitID of ledger.ancestry) {
    const c = ledger.nodes.get(commitID), cached = previousInternal?.authorizationHistory.get(commitID);
    if (cached?.complete && !gap) {
      history.set(commitID, cached);
      bindings = new Map(cached.bindings);
      continue;
    }
    let parsed;
    if (commitID === ledger.head.commitID) parsed = currentManifest;
    else if (Object.hasOwn(files, c.manifestPath)) {
      try {
        parsed = parseJSON(files[c.manifestPath]);
      } catch {
        gap = true;
      }
    }
    if (!parsed) gap = true;
    let result, m;
    try {
      if (gap) fail2("PROJECTION_AUTH_HISTORY_MISSING");
      try {
        m = validateSchema(parsed, "manifest.schema.json");
      } catch {
        fail2("PROJECTION_AUTH_HISTORY_SCHEMA");
      }
      if (hashJSON(m) !== c.manifestHash) fail2("PROJECTION_AUTH_HISTORY_HASH");
      for (const field of ["datasetID", "writerInstanceID", "writerEpoch", "generation"]) if (m[field] !== c[field]) fail2("PROJECTION_AUTH_HISTORY_IDENTITY");
      if (m.schemaVersion.major !== 1) fail2("PROJECTION_AUTH_HISTORY_VERSION");
      if (m.requiredCapabilities.some((x) => !supportedCapabilities.includes(x))) fail2("PROJECTION_AUTH_HISTORY_CAPABILITY");
      if (!Object.hasOwn(m, "projection")) result = { status: "absent" };
      else {
        const version2 = validateSchema(parsed, "common.schema.json", "/$defs/schemaVersion", "/projection/projectionSchemaVersion");
        if (version2.major !== 1) fail2("PROJECTION_VERSION");
        const config = validateSchema(parsed, "manifest.schema.json", "/$defs/projectionConfiguration", "/projection");
        if (config.projectionWriterMode === "direct" && config.projectionWriterInstanceID !== c.writerInstanceID) fail2("PROJECTION_WRITER");
        const old = bindings.get(config.vaultBindingID);
        if (old) {
          const switched = old.projectionWriterMode !== config.projectionWriterMode || old.projectionWriterInstanceID !== config.projectionWriterInstanceID;
          if (config.projectionWriterEpoch < old.projectionWriterEpoch || config.projectionWriterEpoch > old.projectionWriterEpoch + 1 || switched && config.projectionWriterEpoch !== old.projectionWriterEpoch + 1) fail2("PROJECTION_WRITER_EPOCH");
        }
        const locked = deepFreeze(structuredClone(config));
        bindings.set(config.vaultBindingID, locked);
        result = { status: "verified", config: locked };
      }
    } catch (e) {
      const code = e.code?.startsWith("PROJECTION_") ? e.code : "PROJECTION_SCHEMA";
      result = { status: "blocked", code };
      if (code.startsWith("PROJECTION_AUTH_HISTORY_") || code === "PROJECTION_VERSION") gap = true;
    }
    history.set(commitID, { ...result, complete: !gap, bindings: new Map(bindings) });
  }
  return history;
}
function validateGeneration({ commits, files, datasetID, supportedCapabilities = [], previous = null }) {
  try {
    const previousInternal = previous ? verifiedHandles.get(previous) : null;
    if (previous && !previousInternal) fail2("MACHINE_UNVERIFIED_PREVIOUS");
    const ledger = selectHead(commits, datasetID);
    const c = ledger.head;
    const continuesPrevious = !!previous?.commitID && ledger.ancestry.includes(previous.commitID);
    if (previous?.commitID && !continuesPrevious && !(ledger.stale.includes(previous.commitID) && ledger.nodes.get(previous.commitID).writerEpoch < c.writerEpoch)) fail2("LEDGER_ROLLBACK");
    const get = (p) => {
      relativePath(p, { ascii: true });
      if (!Object.hasOwn(files, p)) fail2("MACHINE_MISSING_MEMBER");
      return parseJSON(files[p]);
    };
    const mp = get(c.manifestPath);
    const m = validateSchema(mp, "manifest.schema.json");
    if (hashJSON(m) !== c.manifestHash) fail2("MACHINE_MANIFEST_HASH");
    for (const field of ["datasetID", "writerInstanceID", "writerEpoch", "generation"]) if (m[field] !== c[field]) fail2("MACHINE_IDENTITY");
    if (m.schemaVersion.major !== 1) fail2("MACHINE_VERSION");
    if (m.requiredCapabilities.some((x) => !supportedCapabilities.includes(x))) fail2("MACHINE_CAPABILITY");
    const members = /* @__PURE__ */ new Map(), days = /* @__PURE__ */ new Map();
    let snapshot = null;
    for (const e of m.entries) {
      const rel = memberPath(e);
      if (members.has(rel)) fail2("MACHINE_DUPLICATE_PATH");
      const parsed = get(generationRoot(c) + "/" + rel);
      const v = parsed.value;
      digest(v);
      if (v.contentHash !== e.contentHash) fail2("MACHINE_MEMBER_HASH");
      if (e.kind === "snapshot") {
        snapshot = validateSchema(parsed, "snapshot.schema.json");
        if (snapshot.schemaVersion.major !== 1) fail2("MACHINE_VERSION");
      } else if (e.kind === "day") {
        const d = validateSchema(parsed, "segment.schema.json", "/$defs/dayPackage");
        if (d.schemaVersion.major !== 1) fail2("MACHINE_VERSION");
        days.set(e.dayKey, d);
      } else if (v.projectionKey !== e.projectionKey) fail2("MACHINE_MEMBER_IDENTITY");
      members.set(rel, { entry: e, parsed });
    }
    if (!snapshot) fail2("MACHINE_MISSING_SNAPSHOT");
    const factHistory = new Map(previousInternal?.factHistory ?? []);
    const commonID = [...ledger.ancestry].reverse().find((id) => factHistory.has(id));
    if (previous && !commonID) fail2("MACHINE_ANCESTOR_EVIDENCE_MISSING");
    const inheritedFacts = commonID ? factHistory.get(commonID) : null;
    verifySnapshot(snapshot, m, days, inheritedFacts, c.committedAt);
    factHistory.set(c.commitID, retainFacts(snapshot, inheritedFacts));
    const verified = deepFreeze({ commitID: c.commitID, commit: structuredClone(c), manifest: structuredClone(m), snapshot: structuredClone(snapshot), ancestry: [...ledger.ancestry], stale: [...ledger.stale] });
    const authorizationHistory = projectionHistory(ledger, files, mp, previousInternal, supportedCapabilities);
    verifiedHandles.set(verified, { commit: c, manifest: m, manifestParsed: mp, members, factHistory, authorizationHistory });
    return { status: "promoted", verified };
  } catch (e) {
    return { status: "blocked", scope: "machine", code: e.code ?? "MACHINE_INVALID", previous };
  }
}
function bindProjection(verified, projectionKey, { currentHead = verified.commitID, instanceID, exchangeRoot = "exchange" } = {}) {
  try {
    if (!verifiedHandles.has(verified) || currentHead !== verified.commitID) fail2("PROJECTION_HEAD");
    const internal = verifiedHandles.get(verified);
    const member = internal.members.get(`projections/${projectionKey}.json`);
    if (!member) fail2("PROJECTION_NOT_MEMBER");
    const p = validateSchema(member.parsed, "projection.schema.json");
    const m = internal.manifest;
    const c = internal.commit;
    if (!m.projection) fail2("PROJECTION_CONFIG");
    const authorization = internal.authorizationHistory.get(c.commitID);
    if (authorization?.status !== "verified") fail2(authorization?.code ?? "PROJECTION_CONFIG");
    const config = authorization.config;
    if (config.projectionSchemaVersion.major !== 1 || p.projectionSchemaVersion.major !== 1) fail2("PROJECTION_VERSION");
    if (!validDay(p.dayKey) || p.datasetID !== c.datasetID || p.vaultBindingID !== config.vaultBindingID || p.projectionKey !== projectionKey || p.blockID !== projectionKey) fail2("PROJECTION_IDENTITY");
    const identity2 = { datasetID: p.datasetID, vaultBindingID: p.vaultBindingID, dayKey: p.dayKey, blockRole: p.blockRole };
    if (hashJSON(identity2) !== projectionKey) fail2("PROJECTION_IDENTITY");
    if (p.renderedMarkdown.includes("\r")) fail2("PROJECTION_LF");
    const { sha256: sha2563 } = strict_json_exports;
    if (sha2563(p.renderedMarkdown) !== p.renderedContentHash) fail2("PROJECTION_BODY_HASH");
    if (p.renderedMarkdown.split("\n").some((line) => line.startsWith("<!-- lifeos:"))) fail2("PROJECTION_RESERVED_MARKER");
    relativePath(config.projectionRootRelativePath);
    relativePath(exchangeRoot);
    const a = config.projectionRootRelativePath.toLowerCase(), b = exchangeRoot.toLowerCase();
    if (a === b || a.startsWith(b + "/") || b.startsWith(a + "/")) fail2("PROJECTION_ROOT_OVERLAP");
    if (config.projectionWriterMode === "disabled" || config.projectionWriterInstanceID !== instanceID || config.projectionWriterMode === "direct" && instanceID !== c.writerInstanceID) fail2("PROJECTION_WRITER");
    const payload = deepFreeze(structuredClone(p));
    const binding = deepFreeze(structuredClone(config));
    const bound = Object.freeze({ payload, sourceCommitID: c.commitID, validatedBinding: binding });
    return { status: "bound", bound };
  } catch (e) {
    return { status: "blocked", scope: "projection", code: e.code?.startsWith("PROJECTION_") ? e.code : "PROJECTION_SCHEMA" };
  }
}

// ../../protocol/tools/operations.mjs
var operations_exports = {};
__export(operations_exports, {
  INTENT_TTL_SECONDS: () => INTENT_TTL_SECONDS,
  replayReceipts: () => replayReceipts,
  validateIntent: () => validateIntent
});
var INTENT_TTL_SECONDS = 2592e3;
var TERMINAL = /* @__PURE__ */ new Set(["accepted", "rejected", "expired", "cancelled"]);
var blocked = (code) => ({ state: "blocked", code });
var rejected = (code) => ({ state: "rejected", code });
var wireTime = (value) => {
  const milliseconds = Date.parse(value);
  return typeof value === "string" && Number.isFinite(milliseconds) && new Date(milliseconds).toISOString() === value ? milliseconds : NaN;
};
function replayReceipts(events, operationID, payloadHash, { intentType } = {}) {
  try {
    const bySequence = /* @__PURE__ */ new Map();
    for (const event of events) {
      if (event.operationID !== operationID) continue;
      if (hashOmittingRoot(event, "receiptHash") !== event.receiptHash) {
        return blocked("receipt_hash_mismatch");
      }
      if (event.payloadHash !== payloadHash) return blocked("receipt_payload_mismatch");
      const sequence = event.receiptSequence;
      if (!Number.isSafeInteger(sequence) || sequence < 1) return blocked("receipt_sequence_invalid");
      const previous = bySequence.get(sequence);
      if (previous && previous.receiptHash !== event.receiptHash) return blocked("receipt_sequence_conflict");
      bySequence.set(sequence, event);
    }
    if (!bySequence.size) return { state: "pending" };
    const ordered = [...bySequence.values()].sort((a, b) => a.receiptSequence - b.receiptSequence);
    let terminal;
    for (const event of ordered) {
      if (terminal) return blocked("receipt_after_terminal");
      if (event.status === "received") {
        if (event.receiptSequence !== 1) return blocked("received_sequence_invalid");
      } else if (TERMINAL.has(event.status)) {
        terminal = event;
      } else {
        return blocked("receipt_status_invalid");
      }
    }
    let expectedSequence = 1;
    let previousHash = null;
    let wasReceived = false;
    for (const event of ordered) {
      if (event.receiptSequence !== expectedSequence) return { state: "buffered", code: "receipt_gap" };
      if (event.previousReceiptHash !== previousHash) return blocked("receipt_chain_mismatch");
      if (!Number.isFinite(wireTime(event.emittedAt))) return blocked("receipt_time_invalid");
      if (wasReceived && event.status === "expired") return blocked("expired_after_claim");
      previousHash = event.receiptHash;
      expectedSequence++;
      wasReceived ||= event.status === "received";
    }
    const latest = ordered.at(-1);
    if (latest.status === "received") return { state: "received" };
    if (latest.status === "accepted") {
      if (intentType === "DailyReviewDraft" && (latest.finalEntityID === void 0 || latest.entityRevision === void 0)) {
        return blocked("accepted_entity_missing");
      }
      const result = { state: "accepted" };
      if (latest.finalEntityID !== void 0) result.finalEntityID = latest.finalEntityID;
      if (latest.entityRevision !== void 0) result.entityRevision = latest.entityRevision;
      return result;
    }
    return { state: latest.status, code: latest.errorCode };
  } catch {
    return blocked("receipt_context_invalid");
  }
}
function validateIntent(intent, {
  now,
  knownPayloadHash,
  hasCanonicalReview = false,
  claimed = false,
  originalState
} = {}) {
  try {
    if (hashJSON(intent.payload) !== intent.payloadHash) return rejected("payload_hash_mismatch");
    if (knownPayloadHash != null && knownPayloadHash !== intent.payloadHash) {
      return rejected("operation_payload_conflict");
    }
    const nowTime = typeof now === "number" ? now : now instanceof Date ? now.getTime() : Date.parse(now);
    const createdTime = wireTime(intent.createdAt);
    const expiresTime = wireTime(intent.expiresAt);
    if (![nowTime, createdTime, expiresTime].every(Number.isFinite)) return rejected("invalid_intent_time");
    if (expiresTime <= createdTime || expiresTime - createdTime > INTENT_TTL_SECONDS * 1e3) {
      return rejected("invalid_intent_ttl");
    }
    if (createdTime > nowTime + 3e5) return rejected("invalid_client_clock");
    if (!claimed && nowTime >= expiresTime) return { state: "expired", code: "intent_expired" };
    if (intent.type === "DailyReviewDraft" && hasCanonicalReview) return rejected("conflict_existing_review");
    if (intent.type === "CancelIntent") {
      if (originalState === "accepted") return rejected("already_accepted");
      if (TERMINAL.has(originalState)) return rejected("already_terminal");
    }
    return { state: "valid" };
  } catch {
    return rejected("intent_context_invalid");
  }
}

// disclosure.mjs
var DISCLOSURE = "dayisle.disclosure.v1";
var TYPES = ["Task", "DraftPlan", "CalendarCommitment", "ActualSession", "DailyReview"];
var uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
var hash = /^[0-9a-f]{64}$/;
var historyByHandle = /* @__PURE__ */ new WeakMap();
var fail3 = (code) => {
  throw Error("DISCLOSURE_" + code);
};
var key = (e) => e.entityType + ":" + e.entityID;
var same2 = (a, b) => canonicalize(a) === canonicalize(b);
var exact = (value, keys) => value && typeof value === "object" && !Array.isArray(value) && same2(Object.keys(value).sort(), [...keys].sort());
var identity = (e) => TYPES.includes(e.entityType) && uuid.test(e.entityID ?? "");
var bare = (e) => Object.fromEntries(Object.entries(e).filter(([k]) => k !== "revision" && k !== "contentHash"));
var safe = (n) => Number.isSafeInteger(n) && n > 0;
function grants(value) {
  if (!Array.isArray(value) || value.length > 5e3) fail3("GRANT_LIMIT");
  const result = value.map((e) => {
    if (!exact(e, ["entityType", "entityID", "text"]) || !identity(e) || typeof e.text !== "boolean") fail3("GRANT");
    return { ...e };
  }).sort((a, b) => key(a).localeCompare(key(b)));
  if (new Set(result.map(key)).size !== result.length) fail3("DUPLICATE_GRANT");
  return result;
}
function selectFields(raw, grant, authorized) {
  const fields = { Task: ["lifecycleStatus"], DraftPlan: ["lifecycleStatus", "plannedStart", "plannedEnd", "attributionTimeZone"], CalendarCommitment: raw.allDay ? ["lifecycleStatus", "allDay", "localStartDate", "localEndDateExclusive", "calendarTimeZone"] : ["lifecycleStatus", "allDay", "start", "end", "attributionTimeZone"], ActualSession: ["runState", "factState", "actualStart", "actualEnd", "attributionTimeZone"], DailyReview: ["dayKey"] }[raw.entityType];
  if (!fields) fail3("TYPE");
  const e = { entityType: raw.entityType, entityID: raw.entityID };
  for (const field of fields) if (Object.hasOwn(raw, field)) e[field] = raw[field];
  if (grant.text) {
    const text = raw.entityType === "DailyReview" ? "reflection" : "title";
    if (Object.hasOwn(raw, text)) {
      if (typeof raw[text] !== "string" || raw[text].length > 2e4) fail3("TEXT");
      e[text] = raw[text];
    }
  }
  if (raw.taskID && authorized.has("Task:" + raw.taskID)) e.taskID = raw.taskID;
  return e;
}
function validateDisclosure(input, verified, previous) {
  const files = Object.fromEntries(Object.entries(input.files).map(([p, v]) => [p, Buffer.from(v, "base64")]));
  const ledger = selectHead(input.commits.map((v) => Buffer.from(v, "base64")), input.datasetID);
  let state = { history: /* @__PURE__ */ new Map(), grants: [], epoch: 0, policyHash: null }, started = false, legacy = false;
  for (const id of ledger.ancestry) {
    const c = ledger.nodes.get(id), bytes = files[c.manifestPath];
    if (!bytes) fail3("HISTORY_MISSING");
    const parsed = parseJSON(bytes), m = validateSchema(parsed, "manifest.schema.json");
    if (hashJSON(m) !== c.manifestHash || m.datasetID !== c.datasetID || m.writerInstanceID !== c.writerInstanceID || m.writerEpoch !== c.writerEpoch || m.generation !== c.generation) fail3("HISTORY_HASH");
    const p = m.capabilities.disclosure, required = m.requiredCapabilities.includes(DISCLOSURE);
    if (!required) {
      if (p || started) fail3("CAPABILITY_DOWNGRADE");
      legacy = true;
      continue;
    }
    if (c.takeover !== null || ledger.stale.length) fail3("HANDOVER_UNSUPPORTED");
    if (!exact(p, ["profile", "epoch", "previousPolicyHash", "policyHash", "grants", "stamps"]) || p.profile !== DISCLOSURE || !safe(p.epoch) || !Array.isArray(p.stamps) || p.stamps.length > 1e4) fail3("POLICY");
    assertInteger(parsed, "/capabilities/disclosure/epoch", 1, 9007199254740991);
    const selected = grants(p.grants);
    if (!same2(selected, p.grants)) fail3("GRANT_ORDER");
    if (p.previousPolicyHash !== state.policyHash || p.epoch !== (started ? state.epoch + (same2(selected, state.grants) ? 0 : 1) : 1) || p.policyHash !== hashJSON({ profile: DISCLOSURE, epoch: p.epoch, grants: selected })) fail3("POLICY_CHAIN");
    const authorized = new Map(selected.map((e) => [key(e), e])), history = new Map(state.history), seen = /* @__PURE__ */ new Set();
    for (const [index, stamp] of p.stamps.entries()) {
      assertInteger(parsed, "/capabilities/disclosure/stamps/" + index + "/revision", 1, 9007199254740991);
      if (!exact(stamp, ["entityType", "entityID", "revision", "contentHash", "semanticHash", "state"]) || !identity(stamp) || !safe(stamp.revision) || !hash.test(stamp.contentHash) || !hash.test(stamp.semanticHash) || !["live", "withdrawn", "deleted"].includes(stamp.state) || seen.has(key(stamp))) fail3("STAMP");
      seen.add(key(stamp));
      const prior = history.get(key(stamp));
      if (prior) {
        if (prior.state === "deleted" && !same2(prior, stamp)) fail3("DELETED_ID");
        if (stamp.state === "withdrawn" && (stamp.revision !== prior.revision || stamp.contentHash !== prior.contentHash || stamp.semanticHash !== prior.semanticHash)) fail3("WITHDRAWAL_IS_NOT_FACT_EDIT");
        if (stamp.revision < prior.revision || stamp.revision === prior.revision && (stamp.contentHash !== prior.contentHash || stamp.semanticHash !== prior.semanticHash) || stamp.state === "live" && prior.state === "withdrawn" && stamp.revision <= prior.revision || stamp.state === "deleted" && prior.state !== "deleted" && stamp.revision <= prior.revision) fail3("REVISION");
      } else if (stamp.state !== "live" && !(legacy && !started)) fail3("UNKNOWN_WITHDRAWAL");
      history.set(key(stamp), stamp);
    }
    for (const [id2, stamp] of history) if (stamp.state === "live" !== authorized.has(id2)) fail3("VIEW_SCOPE");
    if ([...authorized.keys()].some((id2) => !history.has(id2))) fail3("MISSING_STAMP");
    const checkpointNeeded = !started && legacy && p.stamps.length > 0 || state.grants.some((g) => {
      const next = authorized.get(key(g));
      return !next || g.text && !next.text;
    });
    if (history.size > 1e4) fail3("HISTORY_LIMIT");
    state = { history, grants: selected, epoch: p.epoch, policyHash: p.policyHash, checkpointNeeded };
    started = true;
  }
  if (historyByHandle.has(previous) && !started) fail3("CAPABILITY_DOWNGRADE");
  if (!started) {
    if (input.requireDisclosure) fail3("PROFILE_REQUIRED");
    return;
  }
  const live = new Map(verified.snapshot.entities.map((e) => [key(e), e])), deleted = new Map(verified.snapshot.tombstones.map((e) => [key(e), e]));
  for (const [id, stamp] of state.history) {
    const e = stamp.state === "live" ? live.get(id) : stamp.state === "deleted" ? deleted.get(id) : null;
    if (stamp.state === "withdrawn") {
      if (live.has(id) || deleted.has(id)) fail3("WITHDRAWN_VISIBLE");
      continue;
    }
    if (!e || e.revision !== stamp.revision || e.contentHash !== stamp.contentHash || hashJSON(bare(e)) !== stamp.semanticHash) fail3("CURRENT_STAMP");
    if (stamp.state === "live") {
      const grant = state.grants.find((g) => key(g) === id), expected = { ...selectFields(e, grant, new Map(state.grants.map((g) => [key(g), g]))), datasetID: e.datasetID };
      if (!same2(expected, bare(e))) fail3("FIELD_ALLOWLIST");
    }
  }
  if (live.size !== state.grants.length || deleted.size !== [...state.history.values()].filter((e) => e.state === "deleted").length) fail3("EXTRA_FACT");
  if (previous && !ledger.ancestry.includes(previous.commitID)) fail3("HANDOVER_UNSUPPORTED");
  for (const entry of verified.manifest.entries.filter((e) => e.kind === "projection")) {
    const p = parseJSON(files[generationRoot(verified.commit) + "/" + memberPath(entry)]).value;
    const identity2 = { datasetID: p.datasetID, vaultBindingID: p.vaultBindingID, dayKey: p.dayKey, blockRole: p.blockRole };
    if (!exact(p, ["projectionKey", "blockID", "datasetID", "vaultBindingID", "dayKey", "blockRole", "blockOwner", "projectionSchemaVersion", "renderedMarkdown", "renderedContentHash", "createIfMissing", "contentHash"]) || !validDay(p.dayKey) || p.datasetID !== verified.commit.datasetID || !uuid.test(p.vaultBindingID ?? "") || p.vaultBindingID !== verified.manifest.projection?.vaultBindingID || p.blockRole !== "daily-summary" || p.blockOwner !== "lifeos" || p.projectionSchemaVersion?.major !== 1 || p.projectionSchemaVersion?.minor !== 0 || p.createIfMissing !== true || p.projectionKey !== hashJSON(identity2) || p.blockID !== p.projectionKey || p.renderedMarkdown !== renderDisclosureDay(verified.snapshot.entities, p.dayKey, verified.commit.committedAt) || p.renderedContentHash !== sha2562(p.renderedMarkdown)) fail3("PROJECTION_DISCLOSURE");
  }
  historyByHandle.set(verified, state);
}
var literal = (text) => String(text).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replace(/[\\`*_{}\[\]()#+!|\-]/g, "\\$&");
var dayInZone2 = (date, zone) => {
  const parts = Object.fromEntries(new Intl.DateTimeFormat("en", { timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(date).map((p) => [p.type, p.value]));
  return parts.year + "-" + parts.month + "-" + parts.day;
};
function renderDisclosureDay(entities, day, now) {
  const lines = ["## \u671D\u5C7F \xB7 " + day, "", "\u5F53\u524D\u6388\u6743\u89C6\u56FE\uFF1B\u4EFB\u52A1\u72B6\u6001\u4E0E\u6587\u5B57\u662F\u672C\u4EE3\u7684\u5F53\u524D\u503C\uFF0C\u4E0D\u5192\u5145\u5F80\u65E5\u5FEB\u7167\u3002"];
  let size = Buffer.byteLength(lines.join("\n"));
  const push = (...rows) => {
    for (const line of rows) {
      size += Buffer.byteLength(line) + 1;
      if (size > 256 * 1024) fail3("PROJECTION_SIZE_LIMIT");
      lines.push(line);
    }
  };
  for (const type of TYPES) {
    const rows = entities.filter((e) => e.entityType === type && (type === "DailyReview" ? e.dayKey === day : type === "Task" ? e.lifecycleStatus === "open" : type === "ActualSession" ? splitSession(e, now).some((s) => s.dayKey === day) : e.lifecycleStatus === "active" && (type === "CalendarCommitment" && e.allDay ? e.localStartDate <= day && e.localEndDateExclusive > day : dayInZone2(new Date(e.plannedStart ?? e.start), e.attributionTimeZone) <= day && dayInZone2(new Date(Date.parse(e.plannedEnd ?? e.end) - 1), e.attributionTimeZone) >= day)));
    if (!rows.length) continue;
    push("", "### " + { Task: "\u60F3\u5B8C\u6210\u7684\u4E8B", DraftPlan: "\u79C1\u4EBA\u8BA1\u5212", CalendarCommitment: "\u65E5\u5386\u627F\u8BFA", ActualSession: "\u5B9E\u9645\u6295\u5165", DailyReview: "\u65E5\u590D\u76D8" }[type]);
    for (const row of rows) if (type === "DailyReview") push(...literal(row.reflection ?? "\u672A\u62AB\u9732\u6B63\u6587").split("\n").map((s) => "> " + s));
    else push("- " + literal(row.title ?? "\u672A\u62AB\u9732\u6807\u9898").replaceAll("\n", " ") + " \xB7 " + literal(row.lifecycleStatus ?? row.factState));
  }
  return lines.join("\n") + "\n";
}

// runtime.mjs
var CAPABILITY = "dayisle.daily-review-text.v1";
var version = { major: 1, minor: 0 };
function decodeInput(input) {
  return { commits: input.commits.map((x) => Buffer.from(x, "base64")), files: Object.fromEntries(Object.entries(input.files).map(([p, v]) => [p, Buffer.from(v, "base64")])), datasetID: input.datasetID, supportedCapabilities: [CAPABILITY, DISCLOSURE] };
}
function verify(input, previous = null) {
  const result = validateGeneration({ ...decodeInput(input), previous });
  if (result.status !== "promoted") return result;
  try {
    if (input.requireDisclosure || result.verified.manifest.requiredCapabilities.includes(DISCLOSURE) || previous?.manifest.requiredCapabilities.includes(DISCLOSURE) || result.verified.manifest.capabilities.disclosure) validateDisclosure(input, result.verified, previous);
    return result;
  } catch (error) {
    return { status: "blocked", scope: "disclosure", code: error.code ?? error.message, previous };
  }
}
function assertReviewPolicy(intent) {
  if (intent.type !== "DailyReviewDraft") return;
  const p = intent.payload;
  if (Object.keys(p).some((k) => !["dayKey", "reflection", "attributionTimeZone"].includes(k)) || !validDay(p.dayKey) || typeof p.reflection !== "string" || !p.reflection.trim() || p.reflection.length > 2e4 || typeof p.attributionTimeZone !== "string") throw Error("REVIEW_PAYLOAD_POLICY");
  try {
    new Intl.DateTimeFormat("en", { timeZone: p.attributionTimeZone }).format(0);
  } catch {
    throw Error("REVIEW_TIMEZONE");
  }
}
function parseIntent(base64, context) {
  const parsed = parseJSON(Buffer.from(base64, "base64")), intent = validateSchema(parsed, "intent.schema.json");
  if (intent.intentSchemaVersion.major !== 1 || intent.capabilityVersion.major !== 1 || intent.datasetID !== context.datasetID || intent.type !== "DailyReviewDraft") throw Error("INTENT_UNSUPPORTED");
  assertReviewPolicy(intent);
  return { intent, validation: validateIntent(intent, context) };
}
function makeIntent({ datasetID, clientID, operationID, dayKey, reflection, zone, now }) {
  const payload = { dayKey, reflection, attributionTimeZone: zone };
  const intent = { intentSchemaVersion: version, capabilityVersion: version, datasetID, clientInstanceID: clientID, operationID, type: "DailyReviewDraft", payload, payloadHash: hashJSON(payload), createdAt: now, expiresAt: new Date(Date.parse(now) + INTENT_TTL_SECONDS * 1e3).toISOString() };
  validateSchema(parseJSON(Buffer.from(canonicalize(intent))), "intent.schema.json");
  assertReviewPolicy(intent);
  return intent;
}

// ../../apps/obsidian-dayisle/main.mjs
var VIEW = "dayisle-panel";
var MAX = 32 * 1024 * 1024;
var cleanPath = (p) => {
  protocol_exports.relativePath(p);
  if (p.startsWith("/") || p.split("/").some((x) => /[ .]$/.test(x))) throw Error("ROOT_PATH");
  return p;
};
var uuid2 = () => {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID().toLowerCase();
  const b = crypto.getRandomValues(new Uint8Array(16));
  b[6] = b[6] & 15 | 64;
  b[8] = b[8] & 63 | 128;
  const hex = Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
  return hex.slice(0, 8) + "-" + hex.slice(8, 12) + "-" + hex.slice(12, 16) + "-" + hex.slice(16, 20) + "-" + hex.slice(20);
};
var dayInZone3 = (date, zone) => {
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-CA", { timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(date).map((x) => [x.type, x.value]));
  return `${p.year}-${p.month}-${p.day}`;
};
var DayislePlugin = class extends import_obsidian.Plugin {
  async onload() {
    this.settings = { root: "LifeOSExchange", clientID: uuid2(), outbox: [], contexts: {}, ...await this.loadData() ?? {} };
    this.lastGood = null;
    this.status = "\u5C1A\u672A\u8BFB\u53D6";
    this.busy = false;
    this.operationStates = [];
    await this.persistSettings(this.settings);
    this.calendarStyle = document.createElement("style");
    this.calendarStyle.dataset.dayisle = "calendar";
    this.calendarStyle.textContent = glass_calendar_default;
    document.head.append(this.calendarStyle);
    this.modals = /* @__PURE__ */ new Set();
    this.registerView(VIEW, (leaf) => new DayisleView(leaf, this));
    this.addRibbonIcon("sun", "\u6253\u5F00\u671D\u5C7F", () => this.open());
    this.addCommand({ id: "open", name: "\u6253\u5F00 Today / Tomorrow / Review", callback: () => this.open() });
    this.addSettingTab(new DayisleSettings(this.app, this));
  }
  onunload() {
    for (const modal of this.modals ?? []) modal.close();
    this.calendarStyle?.remove();
  }
  updateSettings(change) {
    const job = (this.settingsWrites ?? Promise.resolve()).catch(() => {
    }).then(async () => {
      const next = change(this.settings);
      await this.persistSettings(next);
      this.settings = next;
    });
    this.settingsWrites = job;
    return job;
  }
  saveReviewDraft(key2, draft) {
    return this.updateSettings((settings) => ({ ...settings, reviewDrafts: { ...settings.reviewDrafts ?? {}, [key2]: draft } }));
  }
  async open() {
    let leaf = this.app.workspace.getLeavesOfType(VIEW)[0] ?? this.app.workspace.getRightLeaf(false);
    await leaf.setViewState({ type: VIEW, active: true });
    this.app.workspace.revealLeaf(leaf);
  }
  render() {
    for (const leaf of this.app.workspace.getLeavesOfType(VIEW)) leaf.view.render();
  }
  async read(relative, limit = MAX) {
    const path = cleanPath(this.settings.root + "/" + relative), stat = await this.app.vault.adapter.stat(path);
    if (!stat || stat.type !== "file" || stat.size > limit) throw Error("MISSING_OR_OVERSIZE_FILE");
    const bytes = new Uint8Array(await this.app.vault.adapter.readBinary(path));
    this.readBytes += bytes.length;
    if (this.readBytes > MAX) throw Error("EXCHANGE_BUDGET");
    return Buffer.from(bytes);
  }
  async refresh() {
    if (this.busy) return;
    this.busy = true;
    this.readBytes = 0;
    this.render();
    try {
      cleanPath(this.settings.root);
      await this.physicalGuard(false);
      const hints = strict_json_exports.parseJSON(await this.read("current.json", 65536)).value;
      if (typeof hints.datasetID !== "string") throw Error("MISSING_DATASET_HINT");
      const listing = await this.app.vault.adapter.list(this.settings.root + "/commits");
      if (listing.folders.length || listing.files.length > 1e4) throw Error("LEDGER_BUDGET");
      const commits = [];
      for (const file of listing.files) {
        const name = file.slice((this.settings.root + "/commits/").length);
        if (!/^e[1-9][0-9]*-g[1-9][0-9]*-[a-f0-9]{64}\.json$/.test(name)) throw Error("LEDGER_FILENAME");
        commits.push(await this.read("commits/" + name, 65536));
      }
      const ledger = protocol_exports.selectHead(commits, hints.datasetID), files = {};
      const floor = this.settings.readerFloors?.[this.settings.root];
      if (floor && (floor.datasetID !== hints.datasetID || !ledger.ancestry.includes(floor.commitID))) throw Error("READER_HISTORY_ROLLBACK_OR_DATASET_CHANGED");
      for (const id of ledger.ancestry) {
        const c = ledger.nodes.get(id);
        const bytes = await this.read(c.manifestPath, 4 * 1024 * 1024);
        files[c.manifestPath] = bytes;
      }
      const manifest = strict_json_exports.parseJSON(files[ledger.head.manifestPath]).value;
      for (const entry of manifest.entries ?? []) {
        const rel = protocol_exports.generationRoot(ledger.head) + "/" + protocol_exports.memberPath(entry);
        files[rel] = await this.read(rel, entry.kind === "snapshot" ? 16 * 1024 * 1024 : 1024 * 1024);
      }
      const result = verify({ commits, files, datasetID: hints.datasetID, requireDisclosure: true }, this.lastGood);
      if (result.status !== "promoted") throw Error(result.code);
      await this.updateSettings((settings) => ({ ...settings, readerFloors: { ...settings.readerFloors ?? {}, [settings.root]: { datasetID: hints.datasetID, commitID: ledger.head.commitID } } }));
      this.lastGood = result.verified;
      this.status = "\u5DF2\u6821\u9A8C\u5B8C\u6574\u540C\u6B65\u4EE3 \xB7 " + ledger.head.committedAt;
      await this.readReceipts();
    } catch (error) {
      this.status = "\u672C\u6B21\u672A\u63D0\u5347\uFF1A" + (error.code ?? error.message) + "\u3002" + (this.lastGood ? "\u7EE7\u7EED\u663E\u793A\u4E0A\u4E00\u6B21\u5B8C\u6574\u4EE3\u3002" : "\u5C1A\u65E0\u53EF\u7528\u4E8B\u5B9E\u3002");
    } finally {
      this.busy = false;
      this.render();
    }
  }
  async physicalGuard(write) {
    if (!import_obsidian.Platform.isDesktopApp) {
      if (write) throw Error("MOBILE_REQUEST_WRITE_UNVERIFIED");
      return;
    }
    const getBase = this.app.vault.adapter.getBasePath;
    if (typeof getBase !== "function") throw Error("PHYSICAL_GUARD_UNAVAILABLE");
    const fs = window.require("fs"), path = window.require("path");
    const base = fs.realpathSync(getBase.call(this.app.vault.adapter));
    let current = base;
    for (const part of cleanPath(this.settings.root).split("/")) {
      current = path.join(current, part);
      const stat = fs.lstatSync(current);
      if (stat.isSymbolicLink() || !stat.isDirectory()) throw Error("EXCHANGE_SYMLINK");
      const real = fs.realpathSync(current);
      if (real !== base && !real.startsWith(base + path.sep)) throw Error("EXCHANGE_OUTSIDE_VAULT");
    }
    let count = 0;
    const walk = (directory) => {
      for (const item of fs.readdirSync(directory, { withFileTypes: true })) {
        if (++count > 15e3) throw Error("EXCHANGE_BUDGET");
        const full = path.join(directory, item.name), st = fs.lstatSync(full);
        if (st.isSymbolicLink()) throw Error("EXCHANGE_SYMLINK");
        if (st.isDirectory()) walk(full);
        else if (!st.isFile()) throw Error("EXCHANGE_SPECIAL_FILE");
        else if (st.nlink !== 1) throw Error("EXCHANGE_HARDLINK");
      }
    };
    walk(current);
  }
  async submit(intent) {
    if (this.busy) throw Error("BUSY");
    this.busy = true;
    this.render();
    try {
      if (!this.lastGood || intent.datasetID !== this.lastGood.commit.datasetID) throw Error("HEAD_CHANGED");
      const checked = parseIntent(Buffer.from(strict_json_exports.canonicalize(intent)).toString("base64"), { datasetID: this.lastGood.commit.datasetID, now: (/* @__PURE__ */ new Date()).toISOString() });
      if (checked.validation.state !== "valid") throw Error("INTENT_" + checked.validation.state.toUpperCase());
      if (intent.clientInstanceID !== this.settings.clientID) throw Error("CLIENT_CHANGED");
      await this.physicalGuard(true);
      const root = cleanPath(this.settings.root), directory = root + "/intents/" + this.settings.clientID;
      if (!this.settings.outbox.some((x) => x.operationID === intent.operationID)) {
        if (this.settings.outbox.length >= 200) throw Error("OUTBOX_LIMIT_ARCHIVE_COMPLETED_FIRST");
        await this.updateSettings((settings) => ({ ...settings, outbox: [...settings.outbox, intent] }));
      }
      for (const folder of [root + "/intents", directory]) if (!await this.app.vault.adapter.exists(folder)) await this.app.vault.adapter.mkdir(folder);
      await this.physicalGuard(true);
      const target = directory + "/" + intent.operationID + ".json", content = strict_json_exports.canonicalize(intent);
      if (await this.app.vault.adapter.exists(target)) {
        if (await this.app.vault.adapter.read(target) !== content) throw Error("OPERATION_PAYLOAD_CONFLICT");
      } else await this.app.vault.create(target, content);
      new import_obsidian.Notice("\u8349\u7A3F\u8BF7\u6C42\u5DF2\u6392\u961F\u3002\u8BF7\u5728\u624B\u673A\u671D\u5C7F\u9010\u6761\u6838\u5BF9\u5E76\u786E\u8BA4\uFF1B\u8FD9\u91CC\u5C1A\u672A\u751F\u6210\u6B63\u5F0F\u590D\u76D8\u3002");
    } finally {
      this.busy = false;
      this.render();
    }
    await this.refresh();
  }
  async setRoot(value) {
    if (this.busy) throw Error("BUSY");
    cleanPath(value);
    if (value === this.settings.root) return;
    this.busy = true;
    try {
      await this.updateSettings((settings) => {
        const contexts = { ...settings.contexts ?? {}, [settings.root]: { clientID: settings.clientID, outbox: settings.outbox } };
        const selected = contexts[value] ?? { clientID: uuid2(), outbox: [] };
        return { ...settings, root: value, contexts, ...selected };
      });
      this.lastGood = null;
      this.operationStates = [];
      this.status = "\u76EE\u5F55\u5DF2\u53D8\u66F4\uFF0C\u65E7\u76EE\u5F55\u8BF7\u6C42\u5355\u72EC\u4FDD\u7559\uFF1B\u8BF7\u91CD\u65B0\u8BFB\u53D6";
    } finally {
      this.busy = false;
      this.render();
    }
  }
  async persistSettings(value) {
    if (Buffer.byteLength(JSON.stringify(value), "utf8") > 16 * 1024 * 1024 || Object.keys(value.contexts ?? {}).length > 16) throw Error("LOCAL_SETTINGS_BUDGET");
    await this.saveData(value);
  }
  async archiveFinishedRequests() {
    if (this.busy) return;
    this.busy = true;
    try {
      const ids = new Set(this.operationStates.filter((x) => ["accepted", "rejected", "expired", "cancelled"].includes(x.state.state)).map((x) => x.intent.operationID));
      await this.updateSettings((settings) => ({ ...settings, outbox: settings.outbox.filter((x) => !ids.has(x.operationID)) }));
      this.operationStates = this.operationStates.filter((x) => !ids.has(x.intent.operationID));
    } finally {
      this.busy = false;
      this.render();
    }
  }
  async readReceipts() {
    this.operationStates = [];
    for (const intent of this.settings.outbox.filter((x) => x.datasetID === this.lastGood?.commit.datasetID)) {
      try {
        const folder = this.settings.root + "/receipts/" + intent.operationID;
        const events = [];
        if (await this.app.vault.adapter.exists(folder)) {
          const list = await this.app.vault.adapter.list(folder);
          if (list.folders.length || list.files.length > 2) throw Error("RECEIPT_COUNT");
          for (const file of list.files) {
            const name = file.slice(folder.length + 1);
            if (!/^[12]\.json$/.test(name)) throw Error("RECEIPT_PATH");
            const parsed = strict_json_exports.parseJSON(await this.read("receipts/" + intent.operationID + "/" + name, 65536));
            events.push(validateSchema(parsed, "receipt.schema.json"));
          }
        }
        this.operationStates.push({ intent, state: operations_exports.replayReceipts(events, intent.operationID, intent.payloadHash, { intentType: intent.type }) });
      } catch (error) {
        this.operationStates.push({ intent, state: { state: "blocked", code: error.code ?? error.message } });
      }
    }
  }
};
var DayisleView = class extends import_obsidian.ItemView {
  constructor(leaf, plugin) {
    super(leaf);
    this.plugin = plugin;
    this.mode = "Today";
  }
  getViewType() {
    return VIEW;
  }
  getDisplayText() {
    return "\u671D\u5C7F";
  }
  getIcon() {
    return "sun";
  }
  async onOpen() {
    this.render();
  }
  render() {
    const p = this.plugin, root = this.contentEl;
    root.empty();
    root.addClass("dayisle-panel");
    root.createEl("h2", { text: "\u671D\u5C7F \xB7 " + this.mode });
    const nav = root.createDiv();
    for (const mode of ["Today", "Tomorrow", "Review"]) nav.createEl("button", { text: mode }).addEventListener("click", () => {
      this.mode = mode;
      this.render();
    });
    const refresh = root.createEl("button", { text: p.busy ? "\u6B63\u5728\u6821\u9A8C\u2026" : "\u8BFB\u53D6\u5E76\u6821\u9A8C\u540C\u6B65\u4EE3" });
    refresh.disabled = p.busy;
    refresh.addEventListener("click", () => p.refresh());
    root.createEl("p", { text: p.status });
    if (!p.lastGood) {
      root.createEl("p", { text: "\u5148\u5728\u624B\u673A\u671D\u5C7F\u9009\u62E9\u672CVault\uFF0C\u9884\u89C8\u5E76\u53D1\u5E03\u4E00\u6B21\uFF1B\u540C\u6B65\u5B8C\u6210\u540E\u518D\u8BFB\u53D6\u3002" });
      return;
    }
    const verified = p.lastGood, date = /* @__PURE__ */ new Date();
    if (this.mode === "Tomorrow") date.setDate(date.getDate() + 1);
    const day = dayInZone3(date, Intl.DateTimeFormat().resolvedOptions().timeZone), entities = verified.snapshot.entities;
    root.createEl("p", { text: day + " \xB7 \u4E8B\u5B9E\u6765\u81EA\u671D\u5C7F\uFF0C\u6B63\u6587\u7B14\u8BB0\u4E0D\u53CD\u63A8\u4E8B\u5B9E\u3002" });
    const section = (title, items, label) => {
      root.createEl("h3", { text: title });
      if (!items.length) root.createEl("p", { text: "\u8FD9\u4EFD\u540C\u6B65\u4EE3\u91CC\u6CA1\u6709\u6B64\u7C7B\u8BB0\u5F55\u3002" });
      for (const item of items) root.createEl("p", { text: label(item) });
    };
    if (this.mode !== "Review") {
      section("\u4EFB\u52A1", entities.filter((e) => e.entityType === "Task" && e.lifecycleStatus === "open"), (e) => e.title ?? "\u672A\u62AB\u9732\u6807\u9898\u7684\u4EFB\u52A1");
      section("\u79C1\u4EBA\u8BA1\u5212", entities.filter((e) => e.entityType === "DraftPlan" && e.lifecycleStatus === "active" && dayInZone3(new Date(e.plannedStart), e.attributionTimeZone) <= day && dayInZone3(new Date(Date.parse(e.plannedEnd) - 1), e.attributionTimeZone) >= day), (e) => (e.title ?? "\u5B89\u6392") + " \xB7 " + new Date(e.plannedStart).toLocaleString(void 0, { timeZone: e.attributionTimeZone }) + " \xB7 " + e.attributionTimeZone);
      section("\u65E5\u5386\u627F\u8BFA", entities.filter((e) => e.entityType === "CalendarCommitment" && e.lifecycleStatus === "active" && (e.allDay ? e.localStartDate <= day && e.localEndDateExclusive > day : dayInZone3(new Date(e.start), e.attributionTimeZone) <= day && dayInZone3(new Date(Date.parse(e.end) - 1), e.attributionTimeZone) >= day)), (e) => (e.title ?? "\u627F\u8BFA") + (e.allDay ? " \xB7 \u5168\u5929" : " \xB7 " + new Date(e.start).toLocaleString(void 0, { timeZone: e.attributionTimeZone }) + " \xB7 " + e.attributionTimeZone));
      section("\u5B9E\u9645\u6295\u5165", entities.filter((e) => e.entityType === "ActualSession" && protocol_exports.splitSession(e, verified.commit.committedAt).some((s) => s.dayKey === day)), (e) => (e.title ?? "\u5B9E\u9645\u6295\u5165") + " \xB7 " + (e.factState === "confirmed" ? "\u5DF2\u6838\u5BF9" : "\u5F85\u6838\u5BF9") + (e.runState === "running" ? " \xB7 \u8BA1\u65F6\u4E2D" : ""));
    } else {
      section("\u65E5\u590D\u76D8", entities.filter((e) => e.entityType === "DailyReview").sort((a, b) => b.dayKey.localeCompare(a.dayKey)), (e) => e.dayKey + "\n" + (e.reflection ?? "\u672A\u62AB\u9732\u6B63\u6587"));
      const enabled = verified.manifest.capabilities.dailyReviewDraft?.profile === CAPABILITY;
      const button = root.createEl("button", { text: "\u63D0\u4EA4\u7ED9\u624B\u673A\u786E\u8BA4\u7684\u590D\u76D8\u8349\u7A3F" });
      button.disabled = !enabled || !import_obsidian.Platform.isDesktopApp;
      button.addEventListener("click", () => new ReviewModal(this.app, p).open());
      if (!import_obsidian.Platform.isDesktopApp) root.createEl("p", { text: "\u624B\u673A\u63D2\u4EF6\u9762\u677F\u53EA\u8BFB\u3002\u684C\u9762\u63D2\u4EF6\u53EF\u63D0\u4EA4\u8349\u7A3F\u8BF7\u6C42\uFF0C\u518D\u5728\u624B\u673A\u671D\u5C7F\u786E\u8BA4\u3002" });
      for (const item of p.operationStates) {
        root.createEl("p", { text: item.intent.payload.dayKey + " \xB7 \u8BF7\u6C42\u72B6\u6001\uFF1A" + item.state.state + (item.state.code ? " \xB7 " + item.state.code : "") });
        if (item.state.state === "pending") {
          const retry = root.createEl("button", { text: "\u91CD\u8BD5\u540C\u4E00\u8BF7\u6C42" });
          retry.addEventListener("click", () => p.submit(item.intent).catch((error) => new import_obsidian.Notice(error.message)));
        }
      }
      if (p.operationStates.some((x) => ["accepted", "rejected", "expired", "cancelled"].includes(x.state.state))) {
        const archive = root.createEl("button", { text: "\u6536\u8D77\u5DF2\u5904\u7406\u7684\u8BF7\u6C42\uFF08\u4FDD\u7559Vault\u56DE\u6267\uFF09" });
        archive.disabled = p.busy;
        archive.addEventListener("click", () => p.archiveFinishedRequests().catch((error) => new import_obsidian.Notice(error.message)));
      }
    }
    root.createEl("small", { text: "\u7CBE\u786E\u4F4D\u7F6E\u3001\u8DEF\u7EBF\u3001\u7167\u7247\u4E0EEXIF\u4E0D\u4F1A\u8FDB\u5165\u6B64\u540C\u6B65\u3002accepted\u56DE\u6267\u4E0D\u4F1A\u76F4\u63A5\u5192\u5145\u6B63\u5F0F\u4E8B\u5B9E\uFF1B\u9700\u7B49\u4E0B\u4E00\u4EFD\u5408\u6CD5\u540C\u6B65\u4EE3\u3002" });
  }
};
var ReviewModal = class extends import_obsidian.Modal {
  constructor(app, plugin) {
    super(app);
    this.plugin = plugin;
  }
  onOpen() {
    const p = this.plugin, root = this.contentEl;
    root.addClass("dayisle-review");
    p.modals.add(this);
    this.context = { root: p.settings.root, clientID: p.settings.clientID, datasetID: p.lastGood.commit.datasetID };
    this.key = JSON.stringify([this.context.root, this.context.datasetID]);
    const draft = p.settings.reviewDrafts?.[this.key] ?? {};
    this.zone = draft.zone ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
    root.createEl("h2", { text: "\u590D\u76D8\u8349\u7A3F\u8BF7\u6C42" });
    const label = root.createEl("label", { text: "\u590D\u76D8\u65E5\u671F" });
    const date = root.createEl("input", { type: "text", cls: "dayisle-date", attr: { "aria-label": "\u590D\u76D8\u65E5\u671F", readonly: "readonly" } });
    this.date = date;
    date.value = draft.dayKey ?? dayInZone3(/* @__PURE__ */ new Date(), this.zone);
    label.htmlFor = date.id = "dayisle-day-" + uuid2();
    this.calendar = esm_default(date, {
      locale: import_zh.Mandarin,
      dateFormat: "Y-m-d",
      ariaDateFormat: "Y\u5E74m\u6708d\u65E5",
      defaultDate: date.value,
      disableMobile: true,
      monthSelectorType: "static",
      animate: !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
      clickOpens: true,
      onReady: (_, __, instance) => {
        instance.calendarContainer.classList.add("dayisle-calendar");
        instance.calendarContainer.setAttribute("role", "dialog");
        instance.calendarContainer.setAttribute("aria-label", "\u9009\u62E9\u590D\u76D8\u65E5\u671F");
        date.setAttribute("aria-haspopup", "dialog");
        date.setAttribute("aria-expanded", "false");
      },
      onOpen: () => date.setAttribute("aria-expanded", "true"),
      onClose: () => date.setAttribute("aria-expanded", "false"),
      onChange: () => this.queueSave()
    });
    this.text = root.createEl("textarea", { attr: { rows: "8", placeholder: "\u8FD9\u4E00\u5929\u6709\u54EA\u4E9B\u503C\u5F97\u8BB0\u4F4F\u7684\u4E8B\uFF1F", "aria-label": "\u590D\u76D8\u6587\u5B57" } });
    this.text.value = draft.reflection ?? "";
    this.text.addEventListener("input", () => this.queueSave());
    root.createEl("p", { text: "\u5DF2\u6709\u6B63\u5F0F\u590D\u76D8\u65F6\u8BF7\u6C42\u4F1A\u88AB\u62D2\u7EDD\u3002\u53EA\u6709\u624B\u673A\u9010\u6761\u786E\u8BA4\u540E\u624D\u5EFA\u7ACB\u6B63\u5F0F\u590D\u76D8\uFF0C\u4E0D\u8986\u76D6\u5DF2\u6709\u5185\u5BB9\u3002\u5173\u95ED\u6B64\u9875\u4FDD\u7559\u672C\u673A\u8349\u7A3F\u3002\u5F52\u5C5E\u65F6\u533A\uFF1A" + this.zone });
    const send = root.createEl("button", { text: "\u786E\u8BA4\u63D0\u4EA4\u7ED9\u624B\u673A" });
    send.addEventListener("click", async () => {
      send.disabled = true;
      try {
        await this.flushDraft();
        if (p.settings.root !== this.context.root || p.settings.clientID !== this.context.clientID || p.lastGood?.commit.datasetID !== this.context.datasetID) throw Error("\u76EE\u5F55\u5DF2\u53D8\u5316\uFF0C\u8BF7\u5173\u95ED\u5E76\u5728\u539F\u76EE\u5F55\u91CD\u65B0\u6838\u5BF9\u8349\u7A3F");
        const intent = makeIntent({ datasetID: this.context.datasetID, clientID: this.context.clientID, operationID: uuid2(), dayKey: date.value, reflection: this.text.value, zone: this.zone, now: (/* @__PURE__ */ new Date()).toISOString() });
        await p.submit(intent);
        this.sent = true;
        await p.updateSettings((settings) => {
          const drafts = { ...settings.reviewDrafts ?? {} };
          delete drafts[this.key];
          return { ...settings, reviewDrafts: drafts };
        });
        this.close();
      } catch (error) {
        new import_obsidian.Notice("\u672A\u63D0\u4EA4\uFF1A" + error.message);
        send.disabled = false;
      }
    });
  }
  queueSave() {
    clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => this.flushDraft().catch(() => new import_obsidian.Notice("\u8349\u7A3F\u672A\u80FD\u4FDD\u5B58\uFF0C\u8BF7\u5148\u4FDD\u7559\u672C\u9875\u6587\u5B57\u3002")), 350);
  }
  flushDraft() {
    clearTimeout(this.saveTimer);
    if (this.sent || !this.text) return Promise.resolve();
    const draft = { dayKey: this.date.value, reflection: this.text.value, zone: this.zone };
    return this.plugin.saveReviewDraft(this.key, draft);
  }
  onClose() {
    clearTimeout(this.saveTimer);
    const pending = this.flushDraft();
    this.calendar?.destroy();
    this.plugin.modals.delete(this);
    this.contentEl.empty();
    pending.catch(() => new import_obsidian.Notice("\u5173\u95ED\u65F6\u8349\u7A3F\u4FDD\u5B58\u5931\u8D25\uFF0C\u8BF7\u6838\u5BF9\u672C\u673A\u5B58\u50A8\u3002"));
  }
};
var DayisleSettings = class extends import_obsidian.PluginSettingTab {
  constructor(app, plugin) {
    super(app, plugin);
    this.plugin = plugin;
  }
  display() {
    const root = this.containerEl;
    root.empty();
    root.addClass("dayisle-panel");
    root.createEl("h2", { text: "\u671D\u5C7F \xB7 \u4EA4\u6362\u76EE\u5F55" });
    let draft = this.plugin.settings.root;
    new import_obsidian.Setting(root).setName("Vault\u5185\u673A\u5668\u4EA4\u6362\u76EE\u5F55").setDesc("\u9ED8\u8BA4LifeOSExchange\u3002\u8F93\u5165\u540E\u70B9\u51FB\u91C7\u7528\uFF1B\u6BCF\u4E2A\u76EE\u5F55\u7684\u8BF7\u6C42\u5206\u5F00\u4FDD\u7559\uFF0C\u5904\u7406\u671F\u95F4\u4E0D\u80FD\u5207\u6362\u3002").addText((input) => input.setValue(draft).onChange((value) => {
      draft = value;
    })).addButton((button) => button.setButtonText("\u91C7\u7528\u76EE\u5F55").onClick(async () => {
      try {
        await this.plugin.setRoot(draft);
        this.display();
      } catch (error) {
        new import_obsidian.Notice("\u76EE\u5F55\u672A\u91C7\u7528\uFF1A" + error.message);
      }
    }));
    root.createEl("p", { text: "\u672C\u9762\u677F\u4E0D\u4FEE\u6539\u7528\u6237\u7B14\u8BB0\u3002\u684C\u9762\u53D7\u63A7\u8349\u7A3F\u4EC5\u5199\u5165\u6240\u9009\u4EA4\u6362\u6839\u7684intents\u76EE\u5F55\u3002\u624B\u673A\u5BBF\u4E3B\u6CA1\u6709\u53EF\u9A8C\u8BC1\u7684\u7269\u7406\u5199\u5165\u8FB9\u754C\uFF0C\u56E0\u6B64\u624B\u673A\u63D2\u4EF6\u4EC5\u53EA\u8BFB\u3002" });
  }
};
/*! Bundled license information:

ieee754/index.js:
  (*! ieee754. BSD-3-Clause License. Feross Aboukhadijeh <https://feross.org/opensource> *)

buffer/index.js:
  (*!
   * The buffer module from node.js, for the browser.
   *
   * @author   Feross Aboukhadijeh <https://feross.org>
   * @license  MIT
   *)

@noble/hashes/utils.js:
  (*! noble-hashes - MIT License (c) 2022 Paul Miller (paulmillr.com) *)
*/
