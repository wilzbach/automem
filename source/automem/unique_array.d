module automem.unique_array;

import automem.traits: isAllocator;
import automem.test_utils: TestUtils;
import std.traits: isArray;

version(unittest) {
    import unit_threaded;
    import test_allocator: TestAllocator;
}

mixin TestUtils;

struct UniqueArray(Type, Allocator) if(isArray!Type && isAllocator!Allocator) {

    import std.traits: hasMember;
    import std.range: ElementType;

    enum isSingleton = hasMember!(Allocator, "instance");
    alias Element = ElementType!Type;

    static if(isSingleton) {

        /**
           The allocator is a singleton, so no need to pass it in to the
           constructor
        */

        this(size_t size) {
            makeObjects(size);
        }

    } else

        /**
           Non-singleton allocator, must be passed in
         */

        this(Allocator allocator, size_t size) {
            _allocator = allocator;
            makeObjects(size);
        }

    this(T)(UniqueArray!(T, Allocator) other) if(is(T: Type)) {
        moveFrom(other);
    }

    @disable this(this);

    ~this() {
        deleteObjects;
    }

    /**
       Releases ownership and transfers it to the returned
       Unique object.
     */
    UniqueArray unique() {
        import std.algorithm: move;
        UniqueArray u;
        move(this, u);
        assert(_objects.length == 0 && _objects.ptr is null);
        return u;
    }

    /**
       "Truthiness" cast
     */
    bool opCast(T)() const if(is(T == bool)) {
        return _objects.ptr !is null;
    }

    void opAssign(T)(UniqueArray!(T, Allocator) other) if(is(T: Type)) {
        deleteObject;
        moveFrom(other);
    }

    ref inout(Element) opIndex(long i) inout nothrow {
        return _objects[i];
    }

    const(Element)[] opSlice(long i, long j) const nothrow {
        return _objects[i .. j];
    }

    const(Element)[] opSlice() const nothrow {
        return _objects[0 .. length];
    }

    long opDollar() const nothrow {
        return length;
    }

    @property long length() const nothrow {
        return _objects.length;
    }

    @property void length(long i) {
        import std.experimental.allocator: expandArray, shrinkArray;

        if(i > length)
            _allocator.expandArray(_objects, i - length);
        else
            _allocator.shrinkArray(_objects, length - i);
    }

    /**
       Dereference. const  since this otherwise could be used to try
       and append to the array, which would not be nice
     */
    ref const(Type) opUnary(string s)() const if(s == "*") {
        return _objects;
    }

    void opOpAssign(string op)(Element other) if(op == "~") {
        import std.experimental.allocator: expandArray;

        _allocator.expandArray(_objects, 1);
        _objects[$ - 1] = other;
    }

    void opOpAssign(string op)(Type other) if(op == "~") {
        import std.experimental.allocator: expandArray;
        const originalLength = length;
        _allocator.expandArray(_objects, other.length);
        _objects[originalLength .. $] = other[];
    }

    void opOpAssign(string op)(UniqueArray other) if(op == "~") {
        import std.experimental.allocator: expandArray;
        const originalLength = length;
        _allocator.expandArray(_objects, other.length);
        _objects[originalLength .. $] = other[];
    }

    void opAssign(Type other) {
        this.length = other.length;
        _objects[] = other[];
    }

private:

    Type _objects;

    static if(isSingleton)
        alias _allocator = Allocator.instance;
    else
        Allocator _allocator;


    void makeObjects(size_t size) {
        import std.experimental.allocator: makeArray;
        _objects = _allocator.makeArray!Element(size);
    }

    void deleteObjects() {
        deleteObjects(_objects);
    }


    void deleteObjects(Element[] objects) {
        import std.experimental.allocator: dispose;
        import std.traits: isPointer;

        static if(isPointer!Allocator)
            assert((objects.length == 0 && objects.ptr is null) || _allocator !is null);

        if(objects.ptr !is null) _allocator.dispose(objects);
    }

    void moveFrom(T)(ref UniqueArray!(T, Allocator) other) if(is(T: Type)) {
        _object = other._object;
        other._object = null;

        static if(!isSingleton) {
            import std.algorithm: move;
            move(other._allocator, _allocator);
        }
    }
}


@("default TestAllocator")
@system unittest {
    uniqueArrayTest!TestAllocator;
}


@("default Mallocator")
@system unittest {
    import std.experimental.allocator.mallocator: Mallocator;
    uniqueArrayTest!Mallocator;
}

version(unittest) {

    void uniqueArrayTest(T)() {
        import std.traits: hasMember;
        import std.algorithm: move;

        enum isSingleton = hasMember!(T, "instance");

        static if(isSingleton) {

            alias allocator = T.instance;
            alias Allocator = T;
            auto ptr = UniqueArray!(Struct[], Allocator)(3);
            Struct.numStructs += 1; // this ends up at -3 for some reason
        } else {

            auto allocator = T();
            alias Allocator = T*;
            auto ptr = UniqueArray!(Struct[], Allocator)(&allocator, 3);
            Struct.numStructs += 1; // this ends up at -2 for some reason
        }

        ptr.length.shouldEqual(3);

        ptr[2].twice.shouldEqual(0);
        ptr[2] = Struct(5);
        ptr[2].twice.shouldEqual(10);

        ptr[1..$].shouldEqual([Struct(), Struct(5)]);

        typeof(ptr) ptr2;
        move(ptr, ptr2);

        ptr.length.shouldEqual(0);
        (cast(bool)ptr).shouldBeFalse;
        ptr2.length.shouldEqual(3);
        (cast(bool)ptr2).shouldBeTrue;

        // not copyable
        static assert(!__traits(compiles, ptr2 = ptr1));

        auto ptr3 = ptr2.unique;
        ptr3.length.shouldEqual(3);
        ptr3[].shouldEqual([Struct(), Struct(), Struct(5)]);
        (*ptr3).shouldEqual([Struct(), Struct(), Struct(5)]);

        ptr3 ~= Struct(10);
        ptr3[].shouldEqual([Struct(), Struct(), Struct(5), Struct(10)]);

        ptr3 ~= [Struct(11), Struct(12)];
        ptr3[].shouldEqual([Struct(), Struct(), Struct(5), Struct(10), Struct(11), Struct(12)]);

        ptr3.length = 3;
        ptr3[].shouldEqual([Struct(), Struct(), Struct(5)]);

        ptr3.length = 4;
        ptr3[].shouldEqual([Struct(), Struct(), Struct(5), Struct()]);

        ptr3.length = 1;

        static if(isSingleton)
            ptr3 ~= UniqueArray!(Struct[], Allocator)(1);
        else
            ptr3 ~= UniqueArray!(Struct[], Allocator)(&allocator, 1);

        ptr3[].shouldEqual([Struct(), Struct()]);

        static if(isSingleton)
            auto ptr4 = UniqueArray!(Struct[], Allocator)(1);
        else
            auto ptr4 = UniqueArray!(Struct[], Allocator)(&allocator, 1);

        ptr3 ~= ptr4.unique;
        ptr3[].shouldEqual([Struct(), Struct(), Struct()]);

        ptr3 = [Struct(7), Struct(9)];
        ptr3[].shouldEqual([Struct(7), Struct(9)]);
    }
}

@("@nogc")
@system @nogc unittest {

    import std.experimental.allocator.mallocator: Mallocator;

    auto arr = UniqueArray!(NoGcStruct[], Mallocator)(2);
    assert(arr.length == 2);

    arr[0] = NoGcStruct(1);
    arr[1] = NoGcStruct(3);

    {
        NoGcStruct[2] expected = [NoGcStruct(1), NoGcStruct(3)];
        assert(arr[] == expected[]);
    }

    auto arr2 = UniqueArray!(NoGcStruct[], Mallocator)(1);
    arr ~= arr2.unique;

    {
        NoGcStruct[3] expected = [NoGcStruct(1), NoGcStruct(3), NoGcStruct()];
        assert(arr[] == expected[]);
    }
}