// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module cpptooling.generator.adapter;

import std.typecons : Yes, No;
import logger = std.experimental.logger;

import dsrcgen.cpp : CppModule;

import application.types : MainNs, MainInterface;
import cpptooling.analyzer.type;
import cpptooling.data.representation : CppClass, CppNamespace;
import cpptooling.data.type : USRType;

@safe:

/// Make a C++ adapter for an interface.
CppClass makeAdapter(InterfaceT, KindT)(InterfaceT if_name) {
    import cpptooling.data.representation;

    string c_if = cast(string) if_name;
    string c_name = "Adapter";

    auto c = CppClass(CppClassName(c_name));
    c.setKind(KindT.Adapter);

    auto attr = TypeAttr.init;
    attr.isRef = Yes.isRef;
    auto kind = TypeKind(TypeKind.PointerInfo(c_if ~ "%s %s", USRType(c_if ~ "&"), [attr]));

    auto param = makeCxParam(TypeKindVariable(TypeKindAttr(kind,
            TypeAttr.init), CppVariable("inst")));

    c.put("Adapter connecting an interface with an implementation.");
    c.put("The lifetime of the connection is the same as the instance of the adapter.");

    c.put(CppCtor(makeUniqueUSR, CppMethodName(c_name), [param], CppAccess(AccessType.Public)));
    c.put(CppDtor(makeUniqueUSR, CppMethodName("~" ~ c_name),
            CppAccess(AccessType.Public), CppVirtualMethod(MemberVirtualType.Normal)));

    return c;
}

/// make an anonymous namespace containing a ptr to an instance of a test
/// double that implement the interface needed.
CppNamespace makeSingleton(KindT)(MainNs main_ns, MainInterface main_if) {
    import cpptooling.data.representation : CppVariable, CxGlobalVariable,
        makeUniqueUSR;

    auto attr = TypeAttr.init;
    attr.isPtr = Yes.isPtr;
    auto kind = TypeKind(TypeKind.PointerInfo(main_ns ~ "::" ~ main_if ~ "%s %s",
            USRType(main_ns ~ "::" ~ main_if ~ "*"), [attr]));

    auto v = CxGlobalVariable(makeUniqueUSR, TypeKindAttr(kind, TypeAttr.init),
            CppVariable("test_double_inst"));
    auto ns = CppNamespace.makeAnonymous();
    ns.setKind(KindT.TestDoubleSingleton);
    ns.put(v);

    return ns;
}

/** Generate an adapter implementation.
 *
 * Expecting c to only have a c'tor and d'tor.
 * The global is expected to be named test_double_inst.
 */
void generateImpl(CppClass c, CppModule impl) {
    import std.variant : visit;
    import cpptooling.data.representation;
    import dsrcgen.c : E;

    // C'tor is expected to have one parameter.
    static void genCtor(const ref CppClass c, const ref CppCtor m, CppModule impl) {
        import dsrcgen.cpp;
        import cpptooling.data.representation;
        import cpptooling.analyzer.type : TypeKind;

        // dfmt off
        TypeKindVariable p0 = () @trusted {
            import std.array;

            return m.paramRange().front.visit!(
                (TypeKindVariable tkv) => tkv,
                (TypeKindAttr tk) => TypeKindVariable(tk, CppVariable("inst")),
                (VariadicType vt) {
                    logger.error("Variadic c'tor not supported:", m.toString);
                    return TypeKindVariable(makeSimple("not supported"), CppVariable("not supported"));
                })();
        }();
        // dfmt on

        with (impl.ctor_body(m.name, E(p0.type.toStringDecl(p0.name)))) {
            stmt(E("test_double_inst") = E("&" ~ p0.name));
        }
        impl.sep(2);
    }

    //TODO not implemented generator for operators
    static void genOp(const ref CppClass c, const ref CppMethodOp m, CppModule impl) {
    }

    static void genDtor(const ref CppClass c, const ref CppDtor m, CppModule impl) {
        with (impl.dtor_body(c.name)) {
            stmt("test_double_inst = 0");
        }
        impl.sep(2);
    }

    static void genMethod(const ref CppClass c, const ref CppMethod m, CppModule impl) {
        import std.range : takeOne;

        string params = m.paramRange().joinParams();
        auto b = impl.method_body(m.returnType.toStringDecl, c.name, m.name,
                m.isConst ? Yes.isConst : No.isConst, params);
        with (b) {
            auto p = m.paramRange().joinParamNames();
            stmt(E("test_double_inst") = E("&" ~ p));
        }
        impl.sep(2);
    }

    foreach (m; c.methodPublicRange()) {
        // dfmt off
        () @trusted{
            m.visit!(
                (const CppMethod m) => genMethod(c, m, impl),
                (const CppMethodOp m) => genOp(c, m, impl),
                (const CppCtor m) => genCtor(c, m, impl),
                (const CppDtor m) => genDtor(c, m, impl));
        }();
        // dfmt on
    }
}

/// A singleton to allow the adapter to setup "a" connection.
void generateSingleton(CppNamespace in_ns, CppModule impl) {
    import std.ascii : newline;
    import cpptooling.analyzer.type;
    import dsrcgen.cpp : E;

    auto ns = impl.namespace("")[$.begin = "{" ~ newline];
    ns.suppressIndent(1);
    impl.sep(2);

    foreach (g; in_ns.globalRange()) {
        auto stmt = E(g.type.toStringDecl(g.name));
        if (g.type.kind.info.kind == TypeKind.Info.Kind.pointer) {
            stmt = E("0");
        }
        ns.stmt(stmt);
    }
}
