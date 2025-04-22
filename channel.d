import core.thread;
import core.sync.condition;
import core.sync.mutex;

import std.stdio;
import std.sumtype;
import std.meta;
import std.container.dlist;
import std.typecons;

final
class ThreadInfo {
    Mutex m_lock;
    Condition m_putMsg;

    this() nothrow {
        m_lock = new Mutex();
        m_putMsg = new Condition(m_lock);
    }

    // We never use this variable directly.
    // We only use the pointer to yield back control to who notified the thread.
    // FIXME: Race condition two different channels might send something at the same time.
    // The first one will be skipped
    void delegate(void*) on_notify;
    void* notifee;
    void notify(T)(T var) {
        notifee = cast(void*)var;
        m_putMsg.notify;
        if(on_notify) {
            on_notify(cast(void*)var);
        }
    }

    void wait() {
        m_putMsg.wait;
    }

    private static ref thisInfo() nothrow
    {
        static ThreadInfo ti;
        if(!ti) {
            ti = new ThreadInfo();
        }
        return ti;
    }
}

struct Chact(T) {
    Channel!T channel;
    void function(T) action;
}

Chact!T chact(T)(Channel!T channel, void function(T) action) {
    return Chact!T(channel, action);
}

void select(ChannelActions...)(ChannelActions chacts) {
    foreach(chact; chacts) {
        assert(chact.channel.amIListening);
        if(!chact.channel.queue.empty) {
            scope(exit) {
                chact.channel.queue.removeFront;
            }
            chact.action(chact.channel.queue.front);
            return;
        }
    }

    bool received;
    ThreadInfo.thisInfo.on_notify = (void* channel) { 
        foreach(chact; chacts) {
            if(channel is cast(void*)chact.channel) {
                received = true;
                chact.action(cast(chact.channel.Type)channel);
                return;
            }
        }
    };
    while(!received) ThreadInfo.thisInfo.wait;
}

unittest {
    auto cint = new Channel!int;
    auto cchar = new Channel!char;
    cint.listen;
    cchar.listen;
    cchar.send('a');
    /* cint.send(5); */
    select(
        chact( cint, (int) { writeln("Got int"); } ),
        chact( cchar, (char) { writeln("Got char"); } ),
    );
}

class Channel(T) {
    alias Type = T;

    void listen() {
        assert(!ti || amIListening, "somebody else is already listening to this channel");
        ti = ThreadInfo.thisInfo;
    }

    void close() {
        assert(!amIListening, "You cannot close somebody elses channel");
        ti = ThreadInfo.init;
    }

    private:

    DList!T queue;
    ThreadInfo ti;
    Mutex m_lock;


    this() {
        m_lock = new Mutex;
    }

    static if(isSumType!T) {
        static foreach(T2; T.Types) {
            void put(T2 val) {
                send(T(val));
            }
        }
    }
    void send(T val) {
        synchronized(m_lock) {
            queue.insert(val);
            if(ti) {
                ti.notify(this);
            }
        }
    }

    bool amIListening() {
        return ThreadInfo.thisInfo is ti;
    }

    ref T recv() {
        synchronized(m_lock) {
            bool received;
            ti.on_notify = (void* req) {
                if(req is cast(void*)this) {
                    received = true;
                }
            };

            scope(success)
                queue.removeFront();

            // Fixme keep waiting if another channel notified
            if(queue.empty) {
                while(!received) ti.wait();
            }
            return queue.front;
        }
    }
}

class Request(T) {
    ThreadInfo ti;
    this() {
        ti = ThreadInfo.thisInfo;
    }
    
    private T _val;
    private bool finished;
    ref T recv() {
        if(finished) {
            return _val;
        }

        bool received;
        ti.on_notify = (void* req) {
            if(req is cast(void*)this) {
                received = true;
            }
        };
        while(!received) ti.wait;
        return _val;
    }

    void reply(T val) {
        synchronized(ti.m_lock) {
            _val = val;
            finished = true;
            ti.notify(this);
        }
    }
}

unittest {
    auto reqchn = new Request!int();
    reqchn.reply(3);
    assert(reqchn.recv == 3);
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
            chn.listen;
            scope(exit) chn.listen;
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
