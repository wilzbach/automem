module automem.utils;

import std.traits: isFunctionPointer, isDelegate;

template hasNoGcDestructor(T) {

    import std.traits: functionAttributes, FunctionAttribute, hasMember;

    static if(!is(T == class))
        enum hasNoGcDestructor = false;
    else static if(!hasMember!(T, "__dtor"))
        enum hasNoGcDestructor = true;
    else
        enum hasNoGcDestructor = functionAttributes!(typeof(T.__dtor)) & FunctionAttribute.nogc;


}

// enum hasNoGcDestructor(T) = is(T == class) &&
//     (!hasMember!(T, "__dtor") || (functionAttributes!(typeof(T.__dtor)) & FunctionAttribute.nogc));

@("hasNoGcDestructor")
@safe pure unittest {
    static assert(hasNoGcDestructor!NoGc);
    static assert(!hasNoGcDestructor!Gc);
}

// https://www.auburnsounds.com/blog/2016-11-10_Running-D-without-its-runtime.html
void destroyNoGC(T)(T x) nothrow @nogc
    if (is(T == class) || is(T == interface))
{
    assumeNothrowNoGC(
        (T x) {
            return destroy(x);
        })(x);
}

/**
   Assumes a function to be nothrow and @nogc
   From: https://www.auburnsounds.com/blog/2016-11-10_Running-D-without-its-runtime.html
*/
auto assumeNothrowNoGC(T)(T t) if (isFunctionPointer!T || isDelegate!T)
{
    import std.traits: functionAttributes, FunctionAttribute, SetFunctionAttributes, functionLinkage;

    enum attrs = functionAttributes!T
               | FunctionAttribute.nogc
               | FunctionAttribute.nothrow_;
    return cast(SetFunctionAttributes!(T, functionLinkage!T, attrs)) t;
}

version(unittest) {
    private class NoGc { ~this() @nogc {} }
    private class Gc { ~this() { }}
}
