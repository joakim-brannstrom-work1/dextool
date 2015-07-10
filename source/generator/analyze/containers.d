/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module generator.analyze.containers;

import std.array : appender;

import std.typecons;

import translator.Type : TypeKind, makeTypeKind, duplicate;

import logger = std.experimental.logger;

public:

/// Name of a C++ namespace.
alias CppNs = Typedef!(string, string.init, "CppNs");
/// Stack of nested C++ namespaces.
alias CppNsStack = CppNs[];
/// Nesting of C++ namespaces as a string.
alias CppNsNesting = Typedef!(string, string.init, "CppNsNesting");

alias CppVariable = Typedef!(string, string.init, "CppVariable");
alias TypeKindVariable = Tuple!(TypeKind, "type", CppVariable, "name");
alias CppParam = Typedef!(TypeKindVariable, TypeKindVariable.init, "CppParam");
alias CppReturnType = Typedef!(TypeKind, TypeKind.init, "CppReturnType");

// Types for classes
alias CppClassName = Typedef!(string, string.init, "CppClassName");
alias CppClassNesting = Typedef!(string, string.init, "CppNesting");
alias CppVirtualClass = Typedef!(VirtualType, VirtualType.No, "CppVirtualClass");

// Types for methods
alias CppMethodName = Typedef!(string, string.init, "CppMethodName");
alias CppConstMethod = Typedef!(bool, bool.init, "CppConstMethod");
alias CppVirtualMethod = Typedef!(VirtualType, VirtualType.No, "CppVirtualMethod");
alias CppMethodAccess = Typedef!(AccessType, AccessType.Private, "CppMethodAccess");

// Types for free functions
alias CFunctionName = Typedef!(string, string.init, "CFunctionName");
alias CParam = Typedef!(TypeKindVariable, TypeKindVariable.init, "CppParam");
alias CReturnType = Typedef!(TypeKind, TypeKind.init, "CppReturnType");

enum VirtualType {
    No,
    Yes,
    Pure
}

enum AccessType {
    Public,
    Protected,
    Private
}

pure @safe nothrow struct CFunction {
    @disable this();

    this(const CFunctionName name, const CParam[] params_, const CReturnType return_type) {
        this.name = name;
        this.returnType_ = duplicate(cast(const TypedefType!CReturnType) return_type);

        //TODO how do you replace this with a range?
        CParam[] tmp;
        foreach (p; params_) {
            tmp ~= CParam(TypeKindVariable(duplicate(p.type), p.name));
        }
        this.params = tmp;
    }

    /// Function with no parameters.
    this(const CFunctionName name, const CReturnType return_type) {
        this(name, CParam[].init, return_type);
    }

    /// Function with no parameters and returning void.
    this(const CFunctionName name) {
        CReturnType void_ = makeTypeKind("void", "void", false, false, false);
        this(name, CParam[].init, void_);
    }

    auto paramRange() @nogc @safe pure nothrow {
        import std.array;

        return params[];
    }

    invariant() {
        assert(name.length > 0);
        assert(returnType_.name.length > 0);
        assert(returnType_.toString.length > 0);

        foreach (p; params) {
            assert(p.name.length > 0);
            assert(p.type.name.length > 0);
            assert(p.type.toString.length > 0);
        }
    }

    @property auto returnType() const pure @safe {
        return this.returnType_;
    }

    string toString() @safe pure {
        import std.array;
        import std.algorithm : each;
        import std.format : formattedWrite;
        import std.range : takeOne;

        auto ps = appender!string();
        auto pr = paramRange();
        pr.takeOne.each!(a => formattedWrite(ps, "%s %s", a.type.toString, a.name.str));
        if (!pr.empty) {
            pr.popFront;
            pr.each!(a => formattedWrite(ps, ", %s %s", a.type.toString, a.name.str));
        }

        auto rval = appender!string();
        formattedWrite(rval, "%s %s(%s);", returnType.toString, name.str, ps.data);

        return rval.data;
    }

    immutable CFunctionName name;

private:
    CParam[] params;
    CReturnType returnType_;
}

pure @safe nothrow struct CppMethod {
    @disable this();

    this(const CppMethodName name, const CppParam[] params_,
        const CppReturnType return_type, const CppMethodAccess access,
        const CppConstMethod const_, const CppVirtualMethod virtual) {
        this.name = name;
        this.returnType = duplicate(cast(const TypedefType!CppReturnType) return_type);
        this.accessType = access;
        this.isConst = cast(TypedefType!CppConstMethod) const_;
        this.isVirtual = cast(TypedefType!CppVirtualMethod) virtual;

        //TODO how do you replace this with a range?
        CppParam[] tmp;
        foreach (p; params_) {
            tmp ~= CppParam(TypeKindVariable(duplicate(p.type), p.name));
        }
        this.params = tmp;
    }

    /// Function with no parameters.
    this(const CppMethodName name, const CppReturnType return_type,
        const CppMethodAccess access, const CppConstMethod const_, const CppVirtualMethod virtual) {
        this(name, CppParam[].init, return_type, access, const_, virtual);
    }

    /// Function with no parameters and returning void.
    this(const CppMethodName name, const CppMethodAccess access,
        const CppConstMethod const_ = false, const CppVirtualMethod virtual = VirtualType.No) {
        CppReturnType void_ = makeTypeKind("void", "void", false, false, false);
        this(name, CppParam[].init, void_, access, const_, virtual);
    }

    void put(CppParam p) {
        params ~= p;
    }

    auto paramRange() @nogc @safe pure nothrow {
        import std.array;

        return params[];
    }

    string toString() @safe pure {
        import std.array;
        import std.algorithm : each;
        import std.format : formattedWrite;
        import std.range : takeOne, dropOne;

        auto ps = appender!string();
        auto pr = paramRange();
        pr.takeOne.each!(a => formattedWrite(ps, "%s %s", a.type.toString, a.name.str));
        if (!pr.empty) {
            pr.dropOne.each!(a => formattedWrite(ps, ", %s %s", a.type.toString, a.name.str));
        }

        auto rval = appender!string();
        switch (isVirtual) {
        case VirtualType.Yes:
        case VirtualType.Pure:
            rval.put("virtual ");
            break;
        default:
        }
        formattedWrite(rval, "%s %s(%s)", returnType.toString, name.str, ps.data);

        if (isConst) {
            rval.put(" const");
        }
        switch (isVirtual) {
        case VirtualType.Pure:
            rval.put(" = 0");
            break;
        default:
        }

        return rval.data;
    }

    invariant() {
        assert(name.length > 0);
        assert(returnType.name.length > 0);
        assert(returnType.toString.length > 0);

        foreach (p; params) {
            assert(p.name.length > 0);
            assert(p.type.name.length > 0);
            assert(p.type.toString.length > 0);
        }
    }

    immutable bool isConst;
    immutable VirtualType isVirtual;
    immutable CppMethodAccess accessType;

private:
    CppMethodName name;
    CppParam[] params;
    CppReturnType returnType;
}

pure @safe nothrow struct CppClass {
    @disable this();

    this(const CppClassName name, const CppVirtualClass virtual = VirtualType.No) {
        this.name = name;
        this.isVirtual = cast(TypedefType!CppVirtualClass) virtual;
    }

    void put(CppMethod method) {
        final switch (cast(TypedefType!CppMethodAccess) method.accessType) {
        case AccessType.Public:
            methods_pub ~= method;
            break;
        case AccessType.Protected:
            methods_prot ~= method;
            break;
        case AccessType.Private:
            methods_priv ~= method;
            break;
        }
    }

    auto methodRange() @nogc @safe pure nothrow {
        import std.range;

        return chain(methods_pub, methods_prot, methods_priv);
    }

    auto methodPublicRange() @nogc @safe pure nothrow {
        import std.range;

        return methods_pub;
    }

    auto methodProtectedRange() @nogc @safe pure nothrow {
        import std.range;

        return methods_prot;
    }

    auto methodPrivateRange() @nogc @safe pure nothrow {
        import std.range;

        return methods_priv;
    }

    string toString() @safe pure {
        import std.array : appender;
        import std.conv : to;
        import std.algorithm : each;
        import std.ascii : newline;
        import std.format : formattedWrite;

        auto r = appender!string();

        formattedWrite(r, "class %s { // isVirtual %s%s", name.str,
            to!string(isVirtual), newline);
        if (methods_pub.length > 0) {
            formattedWrite(r, "public:%s", newline);
            methods_pub.each!(a => formattedWrite(r, "  %s;%s", a.toString, newline));
        }
        if (methods_prot.length > 0) {
            formattedWrite(r, "protected:%s", newline);
            methods_prot.each!(a => formattedWrite(r, "  %s;%s", a.toString, newline));
        }
        if (methods_priv.length > 0) {
            formattedWrite(r, "private:%s", newline);
            methods_priv.each!(a => formattedWrite(r, "  %s;%s", a.toString, newline));
        }
        formattedWrite(r, "}; //Class:%s%s", name.str, newline);

        return r.data;
    }

    invariant() {
        assert(name.length > 0);
    }

    immutable VirtualType isVirtual;

private:
    CppClassName name;
    CppMethod[] methods_pub;
    CppMethod[] methods_prot;
    CppMethod[] methods_priv;
}

pure @safe nothrow struct CppNamespace {
    @disable this();

    static auto makeAnonymous() {
        return CppNamespace(CppNsStack.init);
    }

    /// A namespace without any nesting.
    static auto makeSimple(string name) {
        return CppNamespace([CppNs(name)]);
    }

    this(const CppNsStack stack) {
        if (stack.length > 0) {
            this.name = stack[$ - 1];
        }
        this.isAnonymous = stack.length == 0;
        this.stack = stack.dup;
    }

    void put(CFunction f) {
        funcs ~= f;
    }

    void put(CppClass s) {
        classes ~= s;
    }

    /** The implementation of the stack is such that new elements are appended
     * to the end. Therefor the range normal direction is from the end of the
     * array to the beginning.
     */
    auto nsNestingRange() @nogc @safe pure nothrow {
        static @nogc struct Result {
            CppNsStack stack;
            @property auto front() @safe pure nothrow {
                assert(!empty, "Can't get front of an empty range");
                return stack[$ - 1];
            }

            @property auto back() @safe pure nothrow {
                assert(!empty, "Can't get back of an empty range");
                return stack[0];
            }

            @property void popFront() @safe pure nothrow {
                assert(!empty, "Can't pop front of an empty range");
                stack = stack[0 .. $ - 1];
            }

            @property void popBack() @safe pure nothrow {
                assert(!empty, "Can't pop back of an empty range");
                stack = stack[1 .. $];
            }

            @property bool empty() @safe pure nothrow const {
                return stack.length == 0;
            }

            @property auto save() @safe pure nothrow {
                return Result(stack);
            }
        }

        return Result(stack);
    }

    auto classRange() @nogc @safe pure nothrow {
        import std.array;

        return classes[];
    }

    auto funcRange() @nogc @safe pure nothrow {
        import std.array;

        return funcs[];
    }

    string toString() @safe pure {
        import std.array : appender;
        import std.algorithm : each;
        import std.format : formattedWrite;
        import std.range : takeOne, retro, dropOne;
        import std.ascii : newline;

        auto ns_app = appender!string();
        auto ns_r = nsNestingRange().retro;
        ns_r.takeOne.each!(a => ns_app.put(a.str));
        if (!ns_r.empty) {
            ns_r.dropOne.each!(a => formattedWrite(ns_app, "::%s", a.str));
        }

        auto app = appender!string();
        formattedWrite(app, "namespace %s {%s", ns_app.data, newline);
        classRange.each!(a => formattedWrite(app, "%s", a.toString));
        formattedWrite(app, "} //NS:%s%s", ns_app.data, newline);

        return app.data;
    }

    immutable bool isAnonymous;
    immutable CppNs name;

private:
    CppNsStack stack;
    CppClass[] classes;
    CFunction[] funcs;
}

pure @safe nothrow struct CppRoot {
    void put(CFunction f) {
        funcs ~= f;
    }

    void put(CppClass s) {
        classes ~= s;
    }

    void put(CppNamespace ns) {
        this.ns ~= ns;
    }

    string toString() {
        import std.algorithm : each;
        import std.array : appender;
        import std.ascii : newline;
        import std.format : formattedWrite;

        auto app = appender!string();

        classRange.each!(a => app.put(a.toString));
        app.put(newline);
        namespaceRange.each!(a => app.put(a.toString));

        return app.data;
    }

    auto namespaceRange() @nogc @safe pure nothrow {
        import std.array;

        return ns[];
    }

    auto classRange() @nogc @safe pure nothrow {
        import std.array;

        return classes[];
    }

    auto funcRange() @nogc @safe pure nothrow {
        import std.array;

        return funcs[];
    }

private:
    CppNamespace[] ns;
    CppClass[] classes;
    CFunction[] funcs;
}

string str(T)(T value) @property @safe pure nothrow if (is(T : T!TL, TL : string)) {
    return cast(string) value;
}

//@name("Test of creating a function")
unittest {
    auto f = CFunction(CFunctionName("nothing"));
    assert(f.name == "nothing");
    assert(f.returnType.name == "void");
}

//@name("Test of creating simples CppMethod")
unittest {
    auto m = CppMethod(CppMethodName("voider"), CppMethodAccess(AccessType.Public));
    assert(m.isConst == false);
    assert(m.isVirtual == VirtualType.No);
    assert(m.name == "voider");
    assert(m.params.length == 0);
    assert(m.returnType.name == "void");
    assert(m.accessType == AccessType.Public);
}

//@name("Test of creating a class")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(CppMethodName("voider"), CppMethodAccess(AccessType.Public));
    c.put(m);
    assert(c.methods_pub.length == 1);
    assert(
        c.toString == "class Foo { // isVirtual No\npublic:\n  void voider();\n}; //Class:Foo\n",
        c.toString);
}

//@name("Create an anonymous namespace struct")
unittest {
    import std.conv;

    auto n = CppNamespace(CppNsStack.init);
    assert(n.name.length == 0, text(n.name.length));
    assert(n.isAnonymous == true, text(n.isAnonymous));
}

//@name("Create a namespace struct two deep")
unittest {
    auto stack = [CppNs("foo"), CppNs("bar")];
    auto n = CppNamespace(stack);
    assert(n.name == "bar", cast(string) n.name);
    assert(n.isAnonymous == false);
}

//@name("Test of iterating over parameters in a class")
unittest {
    import std.array : appender;

    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(CppMethodName("voider"), CppMethodAccess(AccessType.Public));
    c.put(m);

    auto app = appender!string();
    foreach (d; c.methodRange) {
        app.put(d.toString);
    }

    assert(app.data == "void voider()", app.data);
}

//@name("Test of toString for a free function")
unittest {
    auto ptk = makeTypeKind("char", "char*", false, false, true);
    auto rtk = makeTypeKind("int", "int", false, false, false);
    auto f = CFunction(CFunctionName("nothing"), [CParam(TypeKindVariable(ptk,
        CppVariable("x"))), CParam(TypeKindVariable(ptk, CppVariable("y")))], CReturnType(rtk));

    assert(f.toString == "int nothing(char* x, char* y);", f.toString);
}

//@name("Test of toString for CppClass")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    c.put(CppMethod(CppMethodName("voider"), CppMethodAccess(AccessType.Public)));

    {
        auto tk = makeTypeKind("int", "int", false, false, false);
        auto m = CppMethod(CppMethodName("fun"), CppReturnType(tk),
            CppMethodAccess(AccessType.Public), CppConstMethod(false),
            CppVirtualMethod(VirtualType.Pure));
        c.put(m);
    }

    {
        auto m = CppMethod(CppMethodName("gun"),
            CppReturnType(makeTypeKind("char", "char*", false, false, true)),
            CppMethodAccess(AccessType.Public), CppConstMethod(false),
            CppVirtualMethod(VirtualType.No));
        m.put(CppParam(TypeKindVariable(makeTypeKind("int", "int", false,
            false, false), CppVariable("x"))));
        m.put(CppParam(TypeKindVariable(makeTypeKind("int", "int", false,
            false, false), CppVariable("y"))));
        c.put(m);
    }

    {
        auto m = CppMethod(CppMethodName("wun"),
            CppReturnType(makeTypeKind("int", "int", false, false, true)),
            CppMethodAccess(AccessType.Public), CppConstMethod(true),
            CppVirtualMethod(VirtualType.No));
        c.put(m);
    }

    assert(c.toString == "class Foo { // isVirtual No
public:
  void voider();
  virtual int fun() = 0;
  char* gun(int x, int y);
  int wun() const;
}; //Class:Foo
",
        c.toString);
}

//@name("Test of toString for CppNamespace")
unittest {
    auto ns = CppNamespace.makeSimple("simple");

    auto c = CppClass(CppClassName("Foo"));
    c.put(CppMethod(CppMethodName("voider"), CppMethodAccess(AccessType.Public)));
    ns.put(c);

    assert(ns.toString == "namespace simple {
class Foo { // isVirtual No
public:
  void voider();
}; //Class:Foo
} //NS:simple
",
        ns.toString);
}

//@name("Test of toString for CppRoot")
unittest {
    CppRoot root;

    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(CppMethodName("voider"), CppMethodAccess(AccessType.Public));
    c.put(m);
    root.put(c);

    root.put(CppNamespace.makeSimple("simple"));

    assert(root.toString == "class Foo { // isVirtual No
public:
  void voider();
}; //Class:Foo

namespace simple {
} //NS:simple
", root.toString);
}
