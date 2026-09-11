// D.Signer / D.Bridge JS surface.
//
// State portals drive signing through `window.ditec`. This file owns that object
// and translates the calls into one request for Autogram macOS.
//
// Ported from slovensko-digital/autogram-extension (EUPL-1.2), which is the
// reference for what the portals actually call. Written in plain JavaScript so
// the extension needs no build step.
//
// The call order the portals use is worth knowing: `addXmlObject` stores the
// document, `sign` only records the signature parameters and returns at once,
// and the *getter* afterwards is what actually signs and hands back the result.

(function () {
  "use strict";

  var CHANNEL_REQUEST = "autogram-macos-request";
  var CHANNEL_RESPONSE = "autogram-macos-response";
  var XDC_XMLNS = "http://data.gov.sk/def/container/xmldatacontainer+xml/1.1";

  var counter = 0;
  var pending = new Map();

  window.addEventListener(CHANNEL_RESPONSE, function (event) {
    var detail = event.detail || {};
    var resolve = pending.get(detail.id);
    if (!resolve) return;
    pending.delete(detail.id);
    resolve(detail.reply);
  });

  function call(kind, request) {
    var id = "autogram-" + Date.now() + "-" + counter++;
    return new Promise(function (resolve) {
      pending.set(id, resolve);
      window.dispatchEvent(new CustomEvent(CHANNEL_REQUEST, {
        detail: { id: id, kind: kind, request: request }
      }));
    });
  }

  function toBase64(text) {
    return btoa(unescape(encodeURIComponent(text)));
  }

  function fromBase64(text) {
    try {
      return decodeURIComponent(escape(atob(text)));
    } catch (e) {
      // Not base64 after all; the portals are not consistent about this.
      return text;
    }
  }

  function emptyToNull(value) {
    return value === undefined || value === null || value === "" ? null : value;
  }

  // MARK: signing session

  var session = {
    object: null,
    signatureId: null,
    digestAlgUri: null,
    signaturePolicyIdentifier: null,
    signed: null
  };

  function reset() {
    session.object = null;
    session.signed = null;
  }

  /**
   * Turns the stored ditec object into the request the app understands.
   *
   * Schema and transformation are handed over decoded: the app base64 encodes
   * them again on the way to the engine, which is where that encoding belongs.
   */
  function buildRequest(overrides) {
    var object = session.object;
    if (!object) throw new Error("Nie je pripravený žiadny dokument na podpis.");
    var options = overrides || {};
    var level = options.level || "XAdES_BASELINE_B";

    if (object.type === "XadesPdf" || object.type === "XadesBpPdf") {
      return {
        requestID: session.signatureId || ("ditec-" + Date.now()),
        filename: (object.objectId || "dokument") + ".pdf",
        content: object.sourcePdfBase64,
        payloadMimeType: "application/pdf;base64",
        signatureLevel: options.level || "PAdES_BASELINE_B"
      };
    }

    var isXdc = object.type === "XadesBpXml" || object.type === "XadesXml"
      || object.type === "XadesBp2Xml" || object.type === "Xades2Xml";
    if (!isXdc) {
      throw new Error("Typ objektu " + object.type + " zatiaľ nie je podporovaný.");
    }

    var xml, schema, transformation, identifier;
    if (object.type === "XadesBpXml") {
      xml = object.xdcXMLData;
      schema = fromBase64(object.xdcUsedXSD);
      transformation = fromBase64(object.xdcUsedXSLT);
      identifier = object.xdcIdentifier && object.xdcIdentifier.indexOf("/") !== -1
        ? object.xdcIdentifier
        : object.xdcIdentifier + "/" + object.xdcVersion;
    } else if (object.type === "XadesBp2Xml") {
      xml = object.sourceXml;
      schema = object.sourceXsd;
      transformation = object.sourceXsl;
      identifier = object.namespaceUri;
    } else {
      xml = object.sourceXml;
      schema = object.sourceXsd;
      transformation = object.sourceXsl;
      identifier = object.namespaceUri;
    }

    return {
      requestID: session.signatureId || ("ditec-" + Date.now()),
      filename: (object.objectId || "formular") + ".xml",
      content: toBase64(xml),
      payloadMimeType: "application/xml;base64",
      signatureLevel: level,
      container: options.container || "ASiC_E",
      eform: {
        containerXmlns: XDC_XMLNS,
        schema: schema,
        transformation: transformation,
        identifier: identifier,
        schemaIdentifier: emptyToNull(object.xsdReferenceURI),
        transformationIdentifier: emptyToNull(object.xslReferenceURI),
        transformationLanguage: emptyToNull(object.xslXSLTLanguage),
        transformationMediaDestinationTypeDescription:
          emptyToNull(object.xslMediaDestinationTypeDescription),
        transformationTargetEnvironment: emptyToNull(object.xslTargetEnvironment),
        embedUsedSchemas: object.xdcIncludeRefs === true,
        autoLoadEform: false,
        fsFormID: null,
        packaging: "ENVELOPING"
      }
    };
  }

  function performSignature(overrides, callback) {
    var request;
    try {
      request = buildRequest(overrides);
    } catch (error) {
      if (callback && callback.onError) callback.onError(error.message);
      return;
    }

    call("sign", JSON.stringify(request)).then(function (reply) {
      if (!reply || reply.ok !== true) {
        var message = (reply && reply.error) || "Podpisovanie zlyhalo.";
        if (callback && callback.onError) callback.onError(message);
        return;
      }
      var parsed;
      try {
        parsed = JSON.parse(reply.response);
      } catch (error) {
        if (callback && callback.onError) callback.onError("Odpoveď sa nepodarilo prečítať.");
        return;
      }
      session.signed = parsed;
      if (callback && callback.onSuccess) callback.onSuccess(parsed.content);
    });
  }

  // MARK: adapters

  function DSigAdapter() {}
  DSigAdapter.prototype = {
    _ready: true,
    SHA1: "http://www.w3.org/2000/09/xmldsig#sha1",
    SHA256: "http://www.w3.org/2001/04/xmlenc#sha256",
    SHA384: "http://www.w3.org/2001/04/xmldsig-more#sha384",
    SHA512: "http://www.w3.org/2001/04/xmlenc#sha512",
    LANG_SK: "SK",
    LANG_EN: "EN",
    XML_VISUAL_TRANSFORM_TXT: "TXT",
    XML_VISUAL_TRANSFORM_HTML: "HTML",
    PDF_CONFORMANCE_LEVEL_1A: 0,
    PDF_CONFORMANCE_LEVEL_1B: 1,
    PDF_CONFORMANCE_LEVEL_NONE: 2,
    ERROR_SIGNING_CANCELLED: 1,

    initialize: function (callback) {
      call("status", null).then(function (reply) {
        if (reply && reply.ok) {
          if (callback && callback.onSuccess) callback.onSuccess();
        } else if (callback && callback.onError) {
          callback.onError((reply && reply.error) || "Autogram macOS nie je dostupný.");
        }
      });
    },

    // Records the parameters only. The portals sign by calling a getter next,
    // which is where the request actually leaves the page.
    sign: function (signatureId, digestAlgUri, signaturePolicyIdentifier, callback) {
      session.signatureId = signatureId;
      session.digestAlgUri = digestAlgUri;
      session.signaturePolicyIdentifier = signaturePolicyIdentifier;
      if (callback && callback.onSuccess) callback.onSuccess();
    },

    setLanguage: function (language, callback) {
      if (callback && callback.onSuccess) callback.onSuccess();
    },
    getVersion: function (callback) {
      if (callback && callback.onSuccess) callback.onSuccess("1.0.0");
    },
    getSignerIdentification: function (callback) {
      if (callback && callback.onSuccess) {
        callback.onSuccess(session.signed ? session.signed.signedBy : "");
      }
    },
    detectSupportedPlatforms: function (platforms, callback) {
      if (callback && callback.onSuccess) callback.onSuccess(["java"]);
    },
    deploy: function (options, callback) {
      if (callback && callback.onSuccess) callback.onSuccess();
    },
    checkPDFACompliance: function (pdf, password, level, callback) {
      if (callback && callback.onSuccess) callback.onSuccess();
    },
    convertToPDFA: function (pdf, password, level, callback) {
      if (callback && callback.onSuccess) callback.onSuccess();
    },
    setWindowSize: function (width, height, callback) {
      if (callback && callback.onSuccess) callback.onSuccess();
    },
    setCertificateFilter: function (filter, callback) {
      if (callback && callback.onSuccess) callback.onSuccess();
    },
    setSigningTimeProcessing: function (displayGui, includeSigningTime, callback) {
      if (callback && callback.onSuccess) callback.onSuccess();
    }
  };

  function storeObject(object, callback) {
    if (session.signed) reset();
    session.object = object;
    if (callback && callback.onSuccess) callback.onSuccess();
  }

  function DSigXadesBpAdapter() {}
  DSigXadesBpAdapter.prototype = Object.create(DSigAdapter.prototype);

  DSigXadesBpAdapter.prototype.addXmlObject = function (
    objectId, objectDescription, objectFormatIdentifier, xdcXMLData, xdcIdentifier,
    xdcVersion, xdcUsedXSD, xsdReferenceURI, xdcUsedXSLT, xslReferenceURI,
    xslMediaDestinationTypeDescription, xslXSLTLanguage, xslTargetEnvironment,
    xdcIncludeRefs, xdcNamespaceURI, callback
  ) {
    storeObject({
      type: "XadesBpXml",
      objectId: objectId,
      objectDescription: objectDescription,
      objectFormatIdentifier: objectFormatIdentifier,
      xdcXMLData: xdcXMLData,
      xdcIdentifier: xdcIdentifier,
      xdcVersion: xdcVersion,
      xdcUsedXSD: xdcUsedXSD,
      xsdReferenceURI: xsdReferenceURI,
      xdcUsedXSLT: xdcUsedXSLT,
      xslReferenceURI: xslReferenceURI,
      xslMediaDestinationTypeDescription: xslMediaDestinationTypeDescription,
      xslXSLTLanguage: xslXSLTLanguage,
      xslTargetEnvironment: xslTargetEnvironment,
      xdcIncludeRefs: xdcIncludeRefs,
      xdcNamespaceURI: xdcNamespaceURI
    }, callback);
  };

  DSigXadesBpAdapter.prototype.addXmlObject2 = function (
    objectId, objectDescription, namespaceUri, sourceXml, sourceXsd, sourceXsl, callback
  ) {
    storeObject({
      type: "XadesBp2Xml",
      objectId: objectId,
      objectDescription: objectDescription,
      namespaceUri: namespaceUri,
      sourceXml: sourceXml,
      sourceXsd: sourceXsd,
      sourceXsl: sourceXsl
    }, callback);
  };

  DSigXadesBpAdapter.prototype.addPdfObject = function (
    objectId, objectDescription, sourcePdfBase64, password, objectFormatIdentifier,
    reqLevel, convert, callback
  ) {
    storeObject({
      type: "XadesBpPdf",
      objectId: objectId,
      objectDescription: objectDescription,
      sourcePdfBase64: sourcePdfBase64,
      password: password,
      objectFormatIdentifier: objectFormatIdentifier,
      reqLevel: reqLevel,
      convert: convert
    }, callback);
  };

  DSigXadesBpAdapter.prototype.getSignatureWithASiCEnvelopeBase64 = function (callback) {
    performSignature({ container: "ASiC_E", packaging: "ENVELOPING", level: "XAdES_BASELINE_B" }, callback);
  };

  function DSigXadesAdapter() {}
  DSigXadesAdapter.prototype = Object.create(DSigAdapter.prototype);

  DSigXadesAdapter.prototype.addXmlObject = function (
    objectId, objectDescription, sourceXml, sourceXsd, namespaceUri,
    xsdReference, sourceXsl, xslReference, callback
  ) {
    storeObject({
      type: "XadesXml",
      objectId: objectId,
      objectDescription: objectDescription,
      sourceXml: sourceXml,
      sourceXsd: sourceXsd,
      namespaceUri: namespaceUri,
      xsdReference: xsdReference,
      sourceXsl: sourceXsl,
      xslReference: xslReference
    }, callback);
  };

  DSigXadesAdapter.prototype.addPdfObject = DSigXadesBpAdapter.prototype.addPdfObject;

  DSigXadesAdapter.prototype.getSignedXmlWithEnvelope = function (callback) {
    performSignature({ level: "XAdES_BASELINE_B" }, callback);
  };

  DSigXadesAdapter.prototype.getSignedXmlWithEnvelopeAndTimeStamp = function (callback) {
    performSignature({ level: "XAdES_BASELINE_T" }, callback);
  };

  DSigXadesAdapter.prototype.getSigningCertificate = function (callback) {
    if (callback && callback.onSuccess) {
      callback.onSuccess(session.signed ? session.signed.issuedBy : "");
    }
  };

  DSigXadesAdapter.prototype.getSigningTime = function (callback) {
    if (callback && callback.onSuccess) callback.onSuccess(new Date().toISOString());
  };

  // MARK: the object the portals reach for

  var ditec = {
    isAutogram: true,
    isAutogramMacOS: true,
    config: { downloadPage: { url: "", title: "" } },
    utils: {
      ERROR_CANCELLED: 1,
      ERROR_GENERAL: -200,
      ERROR_NOT_INSTALLED: -201,
      ERROR_LAUNCH_FAILED: -202,
      ERROR_LAUNCH_FORBIDDEN: -203,
      isDitecError: function () { return true; },
      extendClass: function () {}
    },
    versions: {},
    dSigXadesJs: new DSigXadesAdapter(),
    dSigXadesBpJs: new DSigXadesBpAdapter()
  };

  try {
    Object.defineProperty(window, "ditec", {
      value: ditec,
      writable: false,
      configurable: false
    });
  } catch (error) {
    window.ditec = ditec;
  }
})();
