// Copyright 'dart-universal_io' project authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// ------------------------------------------------------------------
// THIS FILE WAS DERIVED FROM SOURCE CODE UNDER THE FOLLOWING LICENSE
// ------------------------------------------------------------------
//
// Copyright 2012, the Dart project authors. All rights reserved.
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above
//       copyright notice, this list of conditions and the following
//       disclaimer in the documentation and/or other materials provided
//       with the distribution.
//     * Neither the name of Google Inc. nor the names of its
//       contributors may be used to endorse or promote products derived
//       from this software without specific prior written permission.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

part of universal_io.http;

class HttpHeadersImpl implements HttpHeaders {
  final Map<String, List<String>> _headers;
  final String protocolVersion;

  bool _mutable = true; // Are the headers currently mutable?
  List<String> _noFoldingHeaders;

  int _contentLength = -1;
  bool _persistentConnection = true;
  bool _chunkedTransferEncoding = false;
  String _host;
  int _port;

  final int _defaultPortForScheme;

  HttpHeadersImpl(this.protocolVersion,
      {int defaultPortForScheme = HttpClient.defaultHttpPort,
      HttpHeadersImpl initialHeaders})
      : _headers = HashMap<String, List<String>>(),
        _defaultPortForScheme = defaultPortForScheme {
    if (initialHeaders != null) {
      initialHeaders._headers.forEach((name, value) => _headers[name] = value);
      _contentLength = initialHeaders._contentLength;
      _persistentConnection = initialHeaders._persistentConnection;
      _chunkedTransferEncoding = initialHeaders._chunkedTransferEncoding;
      _host = initialHeaders._host;
      _port = initialHeaders._port;
    }
    if (protocolVersion == "1.0") {
      _persistentConnection = false;
      _chunkedTransferEncoding = false;
    }
  }

  bool get chunkedTransferEncoding => _chunkedTransferEncoding;

  set chunkedTransferEncoding(bool chunkedTransferEncoding) {
    _checkMutable();
    if (chunkedTransferEncoding && protocolVersion == "1.0") {
      throw HttpException(
          "Trying to set 'Transfer-Encoding: Chunked' on HTTP 1.0 headers");
    }
    if (chunkedTransferEncoding == _chunkedTransferEncoding) return;
    if (chunkedTransferEncoding) {
      List<String> values = _headers[HttpHeaders.transferEncodingHeader];
      if ((values == null || values.last != "chunked")) {
        // Headers does not specify chunked encoding - add it if set.
        _addValue(HttpHeaders.transferEncodingHeader, "chunked");
      }
      contentLength = -1;
    } else {
      // Headers does specify chunked encoding - remove it if not set.
      remove(HttpHeaders.transferEncodingHeader, "chunked");
    }
    _chunkedTransferEncoding = chunkedTransferEncoding;
  }

  int get contentLength => _contentLength;

  set contentLength(int contentLength) {
    _checkMutable();
    if (protocolVersion == "1.0" &&
        persistentConnection &&
        contentLength == -1) {
      throw HttpException(
          "Trying to clear ContentLength on HTTP 1.0 headers with "
          "'Connection: Keep-Alive' set");
    }
    if (_contentLength == contentLength) return;
    _contentLength = contentLength;
    if (_contentLength >= 0) {
      if (chunkedTransferEncoding) chunkedTransferEncoding = false;
      _set(HttpHeaders.contentLengthHeader, contentLength.toString());
    } else {
      removeAll(HttpHeaders.contentLengthHeader);
      if (protocolVersion == "1.1") {
        chunkedTransferEncoding = true;
      }
    }
  }

  ContentType get contentType {
    var values = _headers["content-type"];
    if (values != null) {
      return ContentType.parse(values[0]);
    } else {
      return null;
    }
  }

  set contentType(ContentType contentType) {
    _checkMutable();
    _set(HttpHeaders.contentTypeHeader, contentType.toString());
  }

  DateTime get date {
    List<String> values = _headers[HttpHeaders.dateHeader];
    if (values != null) {
      try {
        return HttpDate.parse(values[0]);
      } on Exception {
        return null;
      }
    }
    return null;
  }

  set date(DateTime date) {
    _checkMutable();
    // Format "DateTime" header with date in Greenwich Mean Time (GMT).
    String formatted = HttpDate.format(date.toUtc());
    _set("date", formatted);
  }

  DateTime get expires {
    List<String> values = _headers[HttpHeaders.expiresHeader];
    if (values != null) {
      try {
        return HttpDate.parse(values[0]);
      } on Exception {
        return null;
      }
    }
    return null;
  }

  set expires(DateTime expires) {
    _checkMutable();
    // Format "Expires" header with date in Greenwich Mean Time (GMT).
    String formatted = HttpDate.format(expires.toUtc());
    _set(HttpHeaders.expiresHeader, formatted);
  }

  String get host => _host;

  set host(String host) {
    _checkMutable();
    _host = host;
    _updateHostHeader();
  }

  DateTime get ifModifiedSince {
    List<String> values = _headers[HttpHeaders.ifModifiedSinceHeader];
    if (values != null) {
      try {
        return HttpDate.parse(values[0]);
      } on Exception {
        return null;
      }
    }
    return null;
  }

  set ifModifiedSince(DateTime ifModifiedSince) {
    _checkMutable();
    // Format "ifModifiedSince" header with date in Greenwich Mean Time (GMT).
    String formatted = HttpDate.format(ifModifiedSince.toUtc());
    _set(HttpHeaders.ifModifiedSinceHeader, formatted);
  }

  bool get persistentConnection => _persistentConnection;

  set persistentConnection(bool persistentConnection) {
    _checkMutable();
    if (persistentConnection == _persistentConnection) return;
    if (persistentConnection) {
      if (protocolVersion == "1.1") {
        remove(HttpHeaders.connectionHeader, "close");
      } else {
        if (_contentLength == -1) {
          throw HttpException(
              "Trying to set 'Connection: Keep-Alive' on HTTP 1.0 headers with "
              "no ContentLength");
        }
        add(HttpHeaders.connectionHeader, "keep-alive");
      }
    } else {
      if (protocolVersion == "1.1") {
        add(HttpHeaders.connectionHeader, "close");
      } else {
        remove(HttpHeaders.connectionHeader, "keep-alive");
      }
    }
    _persistentConnection = persistentConnection;
  }

  int get port => _port;

  set port(int port) {
    _checkMutable();
    _port = port;
    _updateHostHeader();
  }

  List<String> operator [](String name) => _headers[name.toLowerCase()];

  void add(String name, value) {
    _checkMutable();
    _addAll(_validateField(name), value);
  }

  void clear() {
    _checkMutable();
    _headers.clear();
    _contentLength = -1;
    _persistentConnection = true;
    _chunkedTransferEncoding = false;
    _host = null;
    _port = null;
  }

  void forEach(void f(String name, List<String> values)) {
    _headers.forEach(f);
  }

  void noFolding(String name) {
    if (_noFoldingHeaders == null) _noFoldingHeaders = List<String>();
    _noFoldingHeaders.add(name);
  }

  void remove(String name, Object value) {
    _checkMutable();
    name = _validateField(name);
    value = _validateValue(value);
    List<String> values = _headers[name];
    if (values != null) {
      int index = values.indexOf(value);
      if (index != -1) {
        values.removeRange(index, index + 1);
      }
      if (values.isEmpty) _headers.remove(name);
    }
    if (name == HttpHeaders.transferEncodingHeader && value == "chunked") {
      _chunkedTransferEncoding = false;
    }
  }

  void removeAll(String name) {
    _checkMutable();
    name = _validateField(name);
    _headers.remove(name);
  }

  set(String name, Object value) {
    _checkMutable();
    name = _validateField(name);
    _headers.remove(name);
    if (name == HttpHeaders.transferEncodingHeader) {
      _chunkedTransferEncoding = false;
    }
    _addAll(name, value);
  }

  String toString() {
    StringBuffer sb = StringBuffer();
    _headers.forEach((String name, List<String> values) {
      sb..write(name)..write(": ");
      bool fold = _foldHeader(name);
      for (int i = 0; i < values.length; i++) {
        if (i > 0) {
          if (fold) {
            sb.write(", ");
          } else {
            sb..write("\n")..write(name)..write(": ");
          }
        }
        sb.write(values[i]);
      }
      sb.write("\n");
    });
    return sb.toString();
  }

  String value(String name) {
    name = name.toLowerCase();
    List<String> values = _headers[name];
    if (values == null) return null;
    if (values.length > 1) {
      throw HttpException("More than one value for header $name");
    }
    return values[0];
  }

  // [name] must be a lower-case version of the name.
  void _add(String name, value) {
    assert(name == _validateField(name));
    // Use the length as index on what method to call. This is notable
    // faster than computing hash and looking up in a hash-map.
    switch (name.length) {
      case 4:
        if (HttpHeaders.dateHeader == name) {
          _addDate(name, value);
          return;
        }
        if (HttpHeaders.hostHeader == name) {
          _addHost(name, value);
          return;
        }
        break;
      case 7:
        if (HttpHeaders.expiresHeader == name) {
          _addExpires(name, value);
          return;
        }
        break;
      case 10:
        if (HttpHeaders.connectionHeader == name) {
          _addConnection(name, value);
          return;
        }
        break;
      case 12:
        if (HttpHeaders.contentTypeHeader == name) {
          _addContentType(name, value);
          return;
        }
        break;
      case 14:
        if (HttpHeaders.contentLengthHeader == name) {
          _addContentLength(name, value);
          return;
        }
        break;
      case 17:
        if (HttpHeaders.transferEncodingHeader == name) {
          _addTransferEncoding(name, value);
          return;
        }
        if (HttpHeaders.ifModifiedSinceHeader == name) {
          _addIfModifiedSince(name, value);
          return;
        }
    }
    _addValue(name, value);
  }

  void _addAll(String name, value) {
    assert(name == _validateField(name));
    if (value is Iterable) {
      for (var v in value) {
        _add(name, _validateValue(v));
      }
    } else {
      _add(name, _validateValue(value));
    }
  }

  void _addConnection(String name, value) {
    var lowerCaseValue = value.toLowerCase();
    if (lowerCaseValue == 'close') {
      _persistentConnection = false;
    } else if (lowerCaseValue == 'keep-alive') {
      _persistentConnection = true;
    }
    _addValue(name, value);
  }

  void _addContentLength(String name, value) {
    if (value is int) {
      contentLength = value;
    } else if (value is String) {
      contentLength = int.parse(value);
    } else {
      throw HttpException("Unexpected type for header named $name");
    }
  }

  void _addContentType(String name, value) {
    _set(HttpHeaders.contentTypeHeader, value);
  }

  void _addDate(String name, value) {
    if (value is DateTime) {
      date = value;
    } else if (value is String) {
      _set(HttpHeaders.dateHeader, value);
    } else {
      throw HttpException("Unexpected type for header named $name");
    }
  }

  void _addExpires(String name, value) {
    if (value is DateTime) {
      expires = value;
    } else if (value is String) {
      _set(HttpHeaders.expiresHeader, value);
    } else {
      throw HttpException("Unexpected type for header named $name");
    }
  }

  void _addHost(String name, value) {
    if (value is String) {
      int pos = value.indexOf(":");
      if (pos == -1) {
        _host = value;
        _port = HttpClient.defaultHttpPort;
      } else {
        if (pos > 0) {
          _host = value.substring(0, pos);
        } else {
          _host = null;
        }
        if (pos + 1 == value.length) {
          _port = HttpClient.defaultHttpPort;
        } else {
          try {
            _port = int.parse(value.substring(pos + 1));
          } on FormatException {
            _port = null;
          }
        }
      }
      _set(HttpHeaders.hostHeader, value);
    } else {
      throw HttpException("Unexpected type for header named $name");
    }
  }

  void _addIfModifiedSince(String name, value) {
    if (value is DateTime) {
      ifModifiedSince = value;
    } else if (value is String) {
      _set(HttpHeaders.ifModifiedSinceHeader, value);
    } else {
      throw HttpException("Unexpected type for header named $name");
    }
  }

  void _addTransferEncoding(String name, value) {
    if (value == "chunked") {
      chunkedTransferEncoding = true;
    } else {
      _addValue(HttpHeaders.transferEncodingHeader, value);
    }
  }

  void _addValue(String name, Object value) {
    List<String> values = _headers[name];
    if (values == null) {
      values = List<String>();
      _headers[name] = values;
    }
    if (value is DateTime) {
      values.add(HttpDate.format(value));
    } else if (value is String) {
      values.add(value);
    } else {
      values.add(_validateValue(value.toString()));
    }
  }

  void _build(BytesBuilder builder) {
    for (String name in _headers.keys) {
      List<String> values = _headers[name];
      bool fold = _foldHeader(name);
      var nameData = name.codeUnits;
      builder.add(nameData);
      builder.addByte(_CharCode.COLON);
      builder.addByte(_CharCode.SP);
      for (int i = 0; i < values.length; i++) {
        if (i > 0) {
          if (fold) {
            builder.addByte(_CharCode.COMMA);
            builder.addByte(_CharCode.SP);
          } else {
            builder.addByte(_CharCode.CR);
            builder.addByte(_CharCode.LF);
            builder.add(nameData);
            builder.addByte(_CharCode.COLON);
            builder.addByte(_CharCode.SP);
          }
        }
        builder.add(values[i].codeUnits);
      }
      builder.addByte(_CharCode.CR);
      builder.addByte(_CharCode.LF);
    }
  }

  _checkMutable() {
    if (!_mutable) throw HttpException("HTTP headers are not mutable");
  }

  void _finalize() {
    _mutable = false;
  }

  _foldHeader(String name) {
    if (name == HttpHeaders.setCookieHeader ||
        (_noFoldingHeaders != null && _noFoldingHeaders.contains(name))) {
      return false;
    }
    return true;
  }

  List<Cookie> _parseCookies() {
    // Parse a Cookie header value according to the rules in RFC 6265.
    var cookies = List<Cookie>();
    void parseCookieString(String s) {
      int index = 0;

      bool done() => index == -1 || index == s.length;

      void skipWS() {
        while (!done()) {
          if (s[index] != " " && s[index] != "\t") return;
          index++;
        }
      }

      String parseName() {
        int start = index;
        while (!done()) {
          if (s[index] == " " || s[index] == "\t" || s[index] == "=") break;
          index++;
        }
        return s.substring(start, index);
      }

      String parseValue() {
        int start = index;
        while (!done()) {
          if (s[index] == " " || s[index] == "\t" || s[index] == ";") break;
          index++;
        }
        return s.substring(start, index);
      }

      bool expect(String expected) {
        if (done()) return false;
        if (s[index] != expected) return false;
        index++;
        return true;
      }

      while (!done()) {
        skipWS();
        if (done()) return;
        String name = parseName();
        skipWS();
        if (!expect("=")) {
          index = s.indexOf(';', index);
          continue;
        }
        skipWS();
        String value = parseValue();
        try {
          cookies.add(_Cookie(name, value));
        } catch (_) {
          // Skip it, invalid cookie data.
        }
        skipWS();
        if (done()) return;
        if (!expect(";")) {
          index = s.indexOf(';', index);
          continue;
        }
      }
    }

    List<String> values = _headers[HttpHeaders.cookieHeader];
    if (values != null) {
      values.forEach((headerValue) => parseCookieString(headerValue));
    }
    return cookies;
  }

  void _set(String name, String value) {
    assert(name == _validateField(name));
    List<String> values = List<String>();
    _headers[name] = values;
    values.add(value);
  }

  _updateHostHeader() {
    bool defaultPort = _port == null || _port == _defaultPortForScheme;
    _set("host", defaultPort ? host : "$host:$_port");
  }

  static String _validateField(String field) {
    for (var i = 0; i < field.length; i++) {
      if (!_HttpParser._isTokenChar(field.codeUnitAt(i))) {
        throw FormatException(
            "Invalid HTTP header field name: ${json.encode(field)}");
      }
    }
    return field.toLowerCase();
  }

  static _validateValue(value) {
    if (value is! String) return value;
    for (var i = 0; i < value.length; i++) {
      if (!_HttpParser._isValueChar(value.codeUnitAt(i))) {
        throw FormatException(
            "Invalid HTTP header field value: ${json.encode(value)}");
      }
    }
    return value;
  }
}

class _ContentType extends _HeaderValue implements ContentType {
  String _primaryType = "";
  String _subType = "";

  _ContentType(String primaryType, String subType, String charset,
      Map<String, String> parameters)
      : _primaryType = primaryType,
        _subType = subType,
        super("") {
    if (_primaryType == null) _primaryType = "";
    if (_subType == null) _subType = "";
    _value = "$_primaryType/$_subType";
    if (parameters != null) {
      _ensureParameters();
      parameters.forEach((String key, String value) {
        String lowerCaseKey = key.toLowerCase();
        if (lowerCaseKey == "charset") {
          value = value.toLowerCase();
        }
        this._parameters[lowerCaseKey] = value;
      });
    }
    if (charset != null) {
      _ensureParameters();
      this._parameters["charset"] = charset.toLowerCase();
    }
  }

  _ContentType._();

  String get charset => parameters["charset"];

  String get mimeType => '$primaryType/$subType';

  String get primaryType => _primaryType;

  String get subType => _subType;

  static _ContentType parse(String value) {
    var result = _ContentType._();
    result._parse(value, ";", null, false);
    int index = result._value.indexOf("/");
    if (index == -1 || index == (result._value.length - 1)) {
      result._primaryType = result._value.trim().toLowerCase();
      result._subType = "";
    } else {
      result._primaryType =
          result._value.substring(0, index).trim().toLowerCase();
      result._subType = result._value.substring(index + 1).trim().toLowerCase();
    }
    return result;
  }
}

class _Cookie implements Cookie {
  String name;
  String value;
  DateTime expires;
  int maxAge;
  String domain;
  String path;
  bool httpOnly = false;
  bool secure = false;

  _Cookie([this.name, this.value]) {
    // Default value of httponly is true.
    httpOnly = true;
    _validate();
  }

  _Cookie.fromSetCookieValue(String value) {
    // Parse the 'set-cookie' header value.
    _parseSetCookieValue(value);
  }

  // Parse a 'set-cookie' header value according to the rules in RFC 6265.
  String toString() {
    StringBuffer sb = StringBuffer();
    sb..write(name)..write("=")..write(value);
    if (expires != null) {
      sb..write("; Expires=")..write(HttpDate.format(expires));
    }
    if (maxAge != null) {
      sb..write("; Max-Age=")..write(maxAge);
    }
    if (domain != null) {
      sb..write("; Domain=")..write(domain);
    }
    if (path != null) {
      sb..write("; Path=")..write(path);
    }
    if (secure) sb.write("; Secure");
    if (httpOnly) sb.write("; HttpOnly");
    return sb.toString();
  }

  void _parseSetCookieValue(String s) {
    int index = 0;

    bool done() => index == s.length;

    String parseName() {
      int start = index;
      while (!done()) {
        if (s[index] == "=") break;
        index++;
      }
      return s.substring(start, index).trim();
    }

    String parseValue() {
      int start = index;
      while (!done()) {
        if (s[index] == ";") break;
        index++;
      }
      return s.substring(start, index).trim();
    }

    void parseAttributes() {
      String parseAttributeName() {
        int start = index;
        while (!done()) {
          if (s[index] == "=" || s[index] == ";") break;
          index++;
        }
        return s.substring(start, index).trim().toLowerCase();
      }

      String parseAttributeValue() {
        int start = index;
        while (!done()) {
          if (s[index] == ";") break;
          index++;
        }
        return s.substring(start, index).trim().toLowerCase();
      }

      while (!done()) {
        String name = parseAttributeName();
        String value = "";
        if (!done() && s[index] == "=") {
          index++; // Skip the = character.
          value = parseAttributeValue();
        }
        if (name == "expires") {
          expires = HttpDate._parseCookieDate(value);
        } else if (name == "max-age") {
          maxAge = int.parse(value);
        } else if (name == "domain") {
          domain = value;
        } else if (name == "path") {
          path = value;
        } else if (name == "httponly") {
          httpOnly = true;
        } else if (name == "secure") {
          secure = true;
        }
        if (!done()) index++; // Skip the ; character
      }
    }

    name = parseName();
    if (done() || name.isEmpty) {
      throw HttpException("Failed to parse header value [$s]");
    }
    index++; // Skip the = character.
    value = parseValue();
    _validate();
    if (done()) return;
    index++; // Skip the ; character.
    parseAttributes();
  }

  void _validate() {
    const separators = [
      "(",
      ")",
      "<",
      ">",
      "@",
      ",",
      ";",
      ":",
      "\\",
      '"',
      "/",
      "[",
      "]",
      "?",
      "=",
      "{",
      "}"
    ];
    for (int i = 0; i < name.length; i++) {
      int codeUnit = name.codeUnits[i];
      if (codeUnit <= 32 || codeUnit >= 127 || separators.contains(name[i])) {
        throw FormatException(
            "Invalid character in cookie name, code unit: '$codeUnit'");
      }
    }

    if (value[0] == '"' && value[value.length - 1] == '"') {
      value = value.substring(1, value.length - 1);
    }
    for (int i = 0; i < value.length; i++) {
      int codeUnit = value.codeUnits[i];
      if (!(codeUnit == 0x21 ||
          (codeUnit >= 0x23 && codeUnit <= 0x2B) ||
          (codeUnit >= 0x2D && codeUnit <= 0x3A) ||
          (codeUnit >= 0x3C && codeUnit <= 0x5B) ||
          (codeUnit >= 0x5D && codeUnit <= 0x7E))) {
        throw FormatException(
            "Invalid character in cookie value, code unit: '$codeUnit'");
      }
    }
  }
}

class _HeaderValue implements HeaderValue {
  String _value;
  Map<String, String> _parameters;
  Map<String, String> _unmodifiableParameters;

  _HeaderValue([this._value = "", Map<String, String> parameters]) {
    if (parameters != null) {
      _parameters = HashMap<String, String>.from(parameters);
    }
  }

  Map<String, String> get parameters {
    _ensureParameters();
    if (_unmodifiableParameters == null) {
      _unmodifiableParameters = UnmodifiableMapView(_parameters);
    }
    return _unmodifiableParameters;
  }

  String get value => _value;

  String toString() {
    StringBuffer sb = StringBuffer();
    sb.write(_value);
    if (parameters != null && parameters.isNotEmpty) {
      _parameters.forEach((String name, String value) {
        sb..write("; ")..write(name)..write("=")..write(value);
      });
    }
    return sb.toString();
  }

  void _ensureParameters() {
    if (_parameters == null) {
      _parameters = HashMap<String, String>();
    }
  }

  void _parse(String s, String parameterSeparator, String valueSeparator,
      bool preserveBackslash) {
    int index = 0;

    bool done() => index == s.length;

    void skipWS() {
      while (!done()) {
        if (s[index] != " " && s[index] != "\t") return;
        index++;
      }
    }

    String parseValue() {
      int start = index;
      while (!done()) {
        if (s[index] == " " ||
            s[index] == "\t" ||
            s[index] == valueSeparator ||
            s[index] == parameterSeparator) break;
        index++;
      }
      return s.substring(start, index);
    }

    void expect(String expected) {
      if (done() || s[index] != expected) {
        throw HttpException("Failed to parse header value");
      }
      index++;
    }

    void maybeExpect(String expected) {
      if (s[index] == expected) index++;
    }

    void parseParameters() {
      var parameters = HashMap<String, String>();
      _parameters = UnmodifiableMapView(parameters);

      String parseParameterName() {
        int start = index;
        while (!done()) {
          if (s[index] == " " ||
              s[index] == "\t" ||
              s[index] == "=" ||
              s[index] == parameterSeparator ||
              s[index] == valueSeparator) break;
          index++;
        }
        return s.substring(start, index).toLowerCase();
      }

      String parseParameterValue() {
        if (!done() && s[index] == "\"") {
          // Parse quoted value.
          StringBuffer sb = StringBuffer();
          index++;
          while (!done()) {
            if (s[index] == "\\") {
              if (index + 1 == s.length) {
                throw HttpException("Failed to parse header value");
              }
              if (preserveBackslash && s[index + 1] != "\"") {
                sb.write(s[index]);
              }
              index++;
            } else if (s[index] == "\"") {
              index++;
              break;
            }
            sb.write(s[index]);
            index++;
          }
          return sb.toString();
        } else {
          // Parse non-quoted value.
          var val = parseValue();
          return val == "" ? null : val;
        }
      }

      while (!done()) {
        skipWS();
        if (done()) return;
        String name = parseParameterName();
        skipWS();
        if (done()) {
          parameters[name] = null;
          return;
        }
        maybeExpect("=");
        skipWS();
        if (done()) {
          parameters[name] = null;
          return;
        }
        String value = parseParameterValue();
        if (name == 'charset' && this is _ContentType && value != null) {
          // Charset parameter of ContentTypes are always lower-case.
          value = value.toLowerCase();
        }
        parameters[name] = value;
        skipWS();
        if (done()) return;
        // TODO: Implement support for multi-valued parameters.
        if (s[index] == valueSeparator) return;
        expect(parameterSeparator);
      }
    }

    skipWS();
    _value = parseValue();
    skipWS();
    if (done()) return;
    maybeExpect(parameterSeparator);
    parseParameters();
  }

  static _HeaderValue parse(String value,
      {parameterSeparator = ";", valueSeparator, preserveBackslash = false}) {
    // Parse the string.
    var result = _HeaderValue();
    result._parse(value, parameterSeparator, valueSeparator, preserveBackslash);
    return result;
  }
}
