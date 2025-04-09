import core.thread;
import core.sync.condition;
import core.sync.mutex;

import std.stdio;
import std.sumtype;
import std.meta;
import std.variant;
import std.container.dlist;
import std.typecons;

private final
class ThreadInfo {
    Mutex m_lock;
    Condition m_putMsg;

    this() nothrow {
        m_lock = new Mutex();
        m_putMsg = new Condition(m_lock);
    }

    void* notifee;
    void notify(T)(T var) {
        notifee = cast(void*)var;
        m_putMsg.notify;
    }

    static ref thisInfo() nothrow
    {
        static ThreadInfo ti;
        if(!ti) {
            ti = new ThreadInfo();
        }
        return ti;
    }
}

template ChannelBaseTypes(Channel) {
    static if(isSumType!(Channel.Type)) {
        alias ChannelBaseTypes = Channel.Type.Types;
    }
    else {
        alias ChannelBaseTypes = Channel.Type;
    }
}

static unittest {
    static assert(is(ChannelBaseTypes!(Channel!int) == int));
    static assert(is(ChannelBaseTypes!(Channel!(SumType!int)) == AliasSeq!int));
}

template CompositeTypeTypes(Channels...) {
    alias CompositeTypeTypes = staticMap!(ChannelBaseTypes, Channels);
}

static unittest {
    static assert(is(CompositeTypeTypes!(Channel!int) == AliasSeq!int));
    static assert(is(CompositeTypeTypes!(Channel!(SumType!int)) == AliasSeq!int));

    static assert(is(CompositeTypeTypes!(Channel!(SumType!int), Channel!int) == AliasSeq!(int, int)));
}

template CompositeType(Channels...) {
    alias CompositeType = SumType!(NoDuplicates!(CompositeTypeTypes!(Channels)));
}

static unittest {
    static assert(is(CompositeType!(Channel!int, Channel!long) == SumType!(int, long)));
    static assert(is(CompositeType!(Channel!(SumType!(int, long)), Channel!string) == SumType!(int, long, string)));
    static assert(is(CompositeType!(Channel!(SumType!(int, string)), Channel!string) == SumType!(int, string)));
}

CompositeType!(Channels) select(Channels...)(Channels channels) {
    alias ReturnType = CompositeType!(Channels);
    foreach(channel; channels) {
        channel.listen;
    }
    scope(exit) {
        foreach(channel; channels) {
            channel.close;
        }
    }
    foreach(channel; channels) {
        if(!channel.queue.empty) {
            scope(exit) {
                channel.queue.removeFront;
            }
            return ReturnType(channel.queue.front);
        }
    }


    ThreadInfo.thisInfo.m_putMsg.wait;
    foreach(channel; channels) {
        if(&channel is ThreadInfo.thisInfo.notifee) {
            scope(exit) {
                channel.queue.removeFront;
            }
            return ReturnType(channel.queue.front);
        }
    }

    assert(0, "Got notifyed but nothing in channels");
}

unittest {
    auto i_c = new Channel!int;
    auto str_c = new Channel!string;

    i_c.send(5);
    select(i_c, str_c).match!(
        (int a) {
            writeln("A ", a);
        },
        (string b) {
            writeln("b ", b);
        }
    );
}

class Channel(T) {
    alias Type = T;

    void listen() {
        assert(!ti, "somebody is already listening to this channel");
        ti = ThreadInfo.thisInfo;
    }

    void close() {
        assert(ti == ThreadInfo.thisInfo, "You cannot close somebody elses channel");
        ti = ThreadInfo.init;
    }

    private:

    DList!T queue;
    ThreadInfo ti;
    Mutex m_lock;


    this() {
        m_lock = new Mutex;
    }

    void send(T val) {
        synchronized(m_lock) {
            queue.insert(val);
            if(ti) {
                ti.notify(this);
            }
        }
    }

    ref T recv() {
        synchronized(m_lock) {
            listen();
            scope(exit)
                close();

            scope(success)
                queue.removeFront();

            if(queue.empty) {
                ti.m_putMsg.wait();
            }
            return queue.front;
        }
    }
}

class SendChannel(T) {
    alias Type = T;

    this(C)(C rchannel) {
    }
}

unittest {
    auto a = SumType!(int, long)(5);
    auto b = SumType!(long)(3);
    auto c = SumType!(char)('a');
    a = typeof(a)(b);
    /* a = cast(typeof(a))c; */
}

/// ---- testing stufz ---

struct Msg {
    int a;
    int b;
    string c;
}

void main() {
    auto chn = new Channel!(immutable(Msg)*);
    auto a = new immutable(Msg)( 5, 3, "aaa");
    printf("Main: %p\n", a);
    chn.send(a);

    auto th = new Thread({
            auto b = chn.recv();
            printf("Work: %p\n", b);
            auto c = chn.recv();
            printf("Work: %p\n", c);
    }).start;

    printf("Main: %p\n", a);
    chn.send(a);

    /* foreach(i; 0..10) { */
    /*     auto c = new shared Msg(i, 8, ""); */
    /*     Thread.sleep(10.msecs); */
    /*     chn.send(c); */
    /*     c.asasas = "ccc"; */
    /*     writeln("Main ", c.asasas, &c); */
    /* } */

    th.join();
}
