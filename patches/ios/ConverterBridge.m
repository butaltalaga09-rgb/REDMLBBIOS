#import "ConverterBridge.h"
#import <Python/Python.h>

static dispatch_once_t gPythonOnce;
static BOOL gPythonReady = NO;
static NSString *gPythonError = nil;

static NSString *ConversionLogPath(void) {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documents = paths.firstObject;
    if (documents.length == 0) return nil;
    NSString *folder = [documents stringByAppendingPathComponent:@"Converted"];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return [folder stringByAppendingPathComponent:@"ConversionLog.txt"];
}

static void AppendNativeLog(NSString *message) {
    NSString *path = ConversionLogPath();
    if (path.length == 0) return;
    NSString *line = [NSString stringWithFormat:@"[native] %@\n", message ?: @"(no message)"];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:data attributes:nil];
        return;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (handle == nil) return;
    @try {
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle synchronizeFile];
    } @catch (__unused NSException *exception) {
    } @finally {
        [handle closeFile];
    }
}

static NSString *CurrentPythonError(void) {
    if (!PyErr_Occurred()) return @"No Python exception was set.";
    PyObject *type = NULL, *value = NULL, *traceback = NULL;
    PyErr_Fetch(&type, &value, &traceback);
    PyErr_NormalizeException(&type, &value, &traceback);
    PyObject *textObject = value ? PyObject_Str(value) : (type ? PyObject_Str(type) : NULL);
    const char *utf8 = textObject ? PyUnicode_AsUTF8(textObject) : NULL;
    NSString *message = utf8 ? [NSString stringWithUTF8String:utf8] : @"Could not format Python exception.";
    Py_XDECREF(textObject);
    Py_XDECREF(type);
    Py_XDECREF(value);
    Py_XDECREF(traceback);
    return message;
}

static void AddPathToPython(NSString *path) {
    if (path.length == 0) return;
    PyObject *sysPath = PySys_GetObject("path"); /* borrowed */
    PyObject *pyPath = PyUnicode_FromString(path.fileSystemRepresentation);
    if (sysPath == NULL || pyPath == NULL) {
        Py_XDECREF(pyPath);
        AppendNativeLog(@"Could not allocate Python import path.");
        return;
    }
    if (PyList_Insert(sysPath, 0, pyPath) != 0) {
        AppendNativeLog([NSString stringWithFormat:@"Could not add Python import path: %@", CurrentPythonError()]);
    }
    Py_DECREF(pyPath);
}

static void InitializeEmbeddedPython(void) {
    AppendNativeLog(@"initializing embedded Python");
    NSString *resourceRoot = NSBundle.mainBundle.resourcePath;
    NSString *frameworksRoot = NSBundle.mainBundle.privateFrameworksPath;
    // Python.framework contains the runtime binary, but is not PYTHONHOME.
    // The matching Python-Apple-support slice is bundled as Resources/python
    // and contains lib/python3.12 plus the standard library and extension modules.
    NSString *pythonHome = [resourceRoot stringByAppendingPathComponent:@"python"];
    NSString *pythonFramework = [frameworksRoot stringByAppendingPathComponent:@"Python.framework"];
    NSString *pythonLib = [pythonHome stringByAppendingPathComponent:@"lib"];
    NSString *pythonStdlib = [pythonLib stringByAppendingPathComponent:@"python3.12"];
    NSString *pythonDynload = [pythonStdlib stringByAppendingPathComponent:@"lib-dynload"];
    NSString *pythonApp = [resourceRoot stringByAppendingPathComponent:@"PythonApp"];
    NSString *sitePackages = [pythonApp stringByAppendingPathComponent:@"site-packages"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:pythonFramework]) {
        gPythonError = @"The embedded Python.framework is missing from this IPA.";
        AppendNativeLog(gPythonError);
        return;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:pythonHome] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:pythonLib] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:[pythonStdlib stringByAppendingPathComponent:@"encodings/__init__.py"]] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:pythonDynload]) {
        gPythonError = @"The embedded Python standard library is incomplete. Expected python/lib/python3.12/encodings and lib-dynload.";
        AppendNativeLog([NSString stringWithFormat:@"%@ (home=%@; lib=%@; stdlib=%@; dynload=%@)", gPythonError, pythonHome, pythonLib, pythonStdlib, pythonDynload]);
        return;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:pythonApp]) {
        gPythonError = @"The bundled PythonApp folder is missing from this IPA.";
        AppendNativeLog(gPythonError);
        return;
    }

    AppendNativeLog([NSString stringWithFormat:@"Python home=%@; lib exists; app=%@", pythonHome, pythonApp]);
    setenv("PYTHONHOME", pythonHome.fileSystemRepresentation, 1);
    // Py_Initialize can abort before returning if it cannot locate the filesystem
    // encoding module. Provide the iOS stdlib and extension-module paths explicitly
    // instead of relying solely on runtime path discovery.
    NSString *pythonSearchPath = [NSString stringWithFormat:@"%@:%@:%@:%@", pythonStdlib, pythonDynload, pythonApp, sitePackages];
    setenv("PYTHONPATH", pythonSearchPath.UTF8String, 1);
    setenv("PYTHONDONTWRITEBYTECODE", "1", 1);
    setenv("PYTHONUTF8", "1", 1);
    setenv("PYTHONCOERCECLOCALE", "0", 1);
    AppendNativeLog([NSString stringWithFormat:@"Python search path configured: stdlib=%@; dynload=%@; app=%@; site-packages=%@", pythonStdlib, pythonDynload, pythonApp, sitePackages]);
    setenv("PYTHONNOUSERSITE", "1", 1);
    setenv("PYTHONFAULTHANDLER", "1", 1);

    AppendNativeLog(@"calling Py_InitializeFromConfig with explicit iOS paths");
    /*
     * Do not rely on environment-variable path discovery on iOS.  In the
     * previous build the process died inside Py_Initialize before it could
     * write another log line.  Isolated PyConfig makes the stdlib and
     * extension-module search paths explicit and reports normal init errors.
     */
    PyConfig config;
    PyConfig_InitIsolatedConfig(&config);
    config.use_environment = 0;
    /*
     * Python-Apple-support enables Apple's system-log stream integration by
     * default. In this embedded iOS app, importing _apple_support during
     * Py_InitializeFromConfig fails and returns the exact error shown in the
     * user's screenshot. The app records its own diagnostics to ConversionLog.txt,
     * so use ordinary Python streams instead of the Apple unified-log bridge.
     */
    config.use_system_logger = 0;
    config.user_site_directory = 0;
    config.write_bytecode = 0;
    wchar_t *homeWide = Py_DecodeLocale(pythonHome.fileSystemRepresentation, NULL);
    wchar_t *programWide = Py_DecodeLocale("ishamlbbios", NULL);
    if (homeWide == NULL || programWide == NULL) {
        if (homeWide) PyMem_RawFree(homeWide);
        if (programWide) PyMem_RawFree(programWide);
        PyConfig_Clear(&config);
        gPythonError = @"Could not encode embedded Python paths for initialization.";
        AppendNativeLog(gPythonError);
        return;
    }
    PyStatus configStatus = PyConfig_SetString(&config, &config.home, homeWide);
    if (!PyStatus_Exception(configStatus)) configStatus = PyConfig_SetString(&config, &config.program_name, programWide);
    PyMem_RawFree(homeWide);
    PyMem_RawFree(programWide);
    if (!PyStatus_Exception(configStatus)) {
        config.module_search_paths_set = 1;
        configStatus = PyWideStringList_Append(&config.module_search_paths,
            Py_DecodeLocale(pythonStdlib.fileSystemRepresentation, NULL));
    }
    if (!PyStatus_Exception(configStatus)) {
        wchar_t *dynloadWide = Py_DecodeLocale(pythonDynload.fileSystemRepresentation, NULL);
        if (dynloadWide == NULL) configStatus = PyStatus_Error("Could not encode Python extension path");
        else {
            configStatus = PyWideStringList_Append(&config.module_search_paths, dynloadWide);
            PyMem_RawFree(dynloadWide);
        }
    }
    if (!PyStatus_Exception(configStatus)) {
        wchar_t *appWide = Py_DecodeLocale(pythonApp.fileSystemRepresentation, NULL);
        if (appWide == NULL) configStatus = PyStatus_Error("Could not encode Python app path");
        else {
            configStatus = PyWideStringList_Append(&config.module_search_paths, appWide);
            PyMem_RawFree(appWide);
        }
    }
    if (!PyStatus_Exception(configStatus)) {
        wchar_t *siteWide = Py_DecodeLocale(sitePackages.fileSystemRepresentation, NULL);
        if (siteWide == NULL) configStatus = PyStatus_Error("Could not encode site-packages path");
        else {
            configStatus = PyWideStringList_Append(&config.module_search_paths, siteWide);
            PyMem_RawFree(siteWide);
        }
    }
    if (PyStatus_Exception(configStatus)) {
        gPythonError = [NSString stringWithFormat:@"Python configuration failed: %s",
            configStatus.err_msg ? configStatus.err_msg : "unknown PyConfig error"];
        AppendNativeLog(gPythonError);
        PyConfig_Clear(&config);
        return;
    }
    configStatus = Py_InitializeFromConfig(&config);
    if (PyStatus_Exception(configStatus)) {
        gPythonError = [NSString stringWithFormat:@"Python initialization failed: %s",
            configStatus.err_msg ? configStatus.err_msg : "unknown Py_InitializeFromConfig error"];
        AppendNativeLog(gPythonError);
        PyConfig_Clear(&config);
        return;
    }
    PyConfig_Clear(&config);
    if (!Py_IsInitialized()) {
        gPythonError = @"Could not initialize the embedded Python runtime.";
        AppendNativeLog(gPythonError);
        return;
    }
    AppendNativeLog(@"Python initialized; adding app paths");
    AddPathToPython(sitePackages);
    AddPathToPython(pythonApp);
    if (PyRun_SimpleString("import sys\nsys.dont_write_bytecode = True\n") != 0) {
        gPythonError = [NSString stringWithFormat:@"Python runtime configuration failed: %@", CurrentPythonError()];
        AppendNativeLog(gPythonError);
        PyErr_Clear();
        return;
    }
    gPythonReady = YES;
    AppendNativeLog(@"embedded Python is ready");
    /* Release the GIL so conversion can run on a background task. */
    PyEval_SaveThread();
}

@implementation PythonBridge
+ (NSString *)convertInput:(NSString *)inputPath
                shaderPath:(NSString *)shaderPath
               outputParent:(NSString *)outputParent
                  createZip:(BOOL)createZip
             fullValidation:(BOOL)fullValidation
             preserveShadows:(BOOL)preserveShadows {
    AppendNativeLog([NSString stringWithFormat:@"Convert tapped; input=%@", inputPath.lastPathComponent ?: @"(unknown)"]);
    dispatch_once(&gPythonOnce, ^{ InitializeEmbeddedPython(); });
    if (!gPythonReady) {
        AppendNativeLog([NSString stringWithFormat:@"Python not ready: %@", gPythonError ?: @"unknown initialization error"]);
        return [NSString stringWithFormat:@"{\"ok\":false,\"error\":%@}", [self jsonString:gPythonError ?: @"Embedded Python failed to initialize."]];
    }

    PyGILState_STATE gil = PyGILState_Ensure();
    NSString *answer = nil;
    AppendNativeLog(@"GIL acquired; importing mlbb_ios_bridge");
    PyObject *module = PyImport_ImportModule("mlbb_ios_bridge");
    PyObject *function = module ? PyObject_GetAttrString(module, "convert") : NULL;
    PyObject *args = PyTuple_New(6);
    if (args == NULL) {
        NSString *message = [NSString stringWithFormat:@"Could not allocate Python argument tuple: %@", CurrentPythonError()];
        AppendNativeLog(message);
        PyErr_Clear();
    } else {
        PyObject *values[6] = {
            PyUnicode_FromString(inputPath.fileSystemRepresentation),
            PyUnicode_FromString(shaderPath.fileSystemRepresentation),
            PyUnicode_FromString(outputParent.fileSystemRepresentation),
            PyBool_FromLong(createZip),
            PyBool_FromLong(fullValidation),
            PyBool_FromLong(preserveShadows)
        };
        BOOL valid = YES;
        for (NSUInteger i = 0; i < 6; i++) {
            if (values[i] == NULL) { valid = NO; break; }
        }
        if (valid) {
            for (NSUInteger i = 0; i < 6; i++) PyTuple_SET_ITEM(args, (Py_ssize_t)i, values[i]);
        } else {
            for (NSUInteger i = 0; i < 6; i++) Py_XDECREF(values[i]);
            AppendNativeLog([NSString stringWithFormat:@"Could not allocate Python argument: %@", CurrentPythonError()]);
            PyErr_Clear();
        }
    }

    if (module == NULL || function == NULL) {
        NSString *message = [NSString stringWithFormat:@"Could not load Python conversion bridge: %@", CurrentPythonError()];
        AppendNativeLog(message);
        PyErr_Clear();
    }
    if (function != NULL && args != NULL) {
        BOOL argsReady = YES;
        for (Py_ssize_t i = 0; i < PyTuple_GET_SIZE(args); i++) {
            if (PyTuple_GET_ITEM(args, i) == NULL) { argsReady = NO; break; }
        }
        if (argsReady) {
            AppendNativeLog(@"calling Python convert()");
            PyObject *result = PyObject_CallObject(function, args);
            if (result != NULL) {
                const char *utf8 = PyUnicode_AsUTF8(result);
                answer = utf8 ? [NSString stringWithUTF8String:utf8] : nil;
                if (answer == nil) {
                    AppendNativeLog([NSString stringWithFormat:@"Python result was not UTF-8 text: %@", CurrentPythonError()]);
                    PyErr_Clear();
                }
                Py_DECREF(result);
            } else {
                NSString *message = [NSString stringWithFormat:@"Python convert() raised: %@", CurrentPythonError()];
                AppendNativeLog(message);
                PyErr_Clear();
                answer = [NSString stringWithFormat:@"{\"ok\":false,\"error\":%@}", [self jsonString:message]];
            }
        } else {
            AppendNativeLog(@"Python argument tuple contains an uninitialized slot; call skipped.");
        }
    }
    Py_XDECREF(args);
    Py_XDECREF(function);
    Py_XDECREF(module);
    PyGILState_Release(gil);
    AppendNativeLog(answer.length ? @"Python bridge returned a response" : @"Python bridge returned no response");
    return answer ?: @"{\"ok\":false,\"error\":\"Python conversion bridge failed. Open Files > On My iPhone > ishamlbbios > Converted > ConversionLog.txt.\"}";
}

+ (NSString *)jsonString:(NSString *)string {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[string ?: @"Unknown error"] options:0 error:nil];
    if (data == nil) return @"\"Embedded Python failed to initialize.\"";
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (json.length >= 2) return [json substringWithRange:NSMakeRange(1, json.length - 2)];
    return @"\"Embedded Python failed to initialize.\"";
}
@end
