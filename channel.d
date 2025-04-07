import core.thread;
import core.sync.condition;
import core.sync.mutex;

import std.stdio;
import std.variant;
import std.container.dlist;

private final
class ThreadInfo {
    Mutex m_lock;
    Condition m_putMsg;

    this() nothrow {
        m_lock = new Mutex();
        m_putMsg = new Condition(m_lock);
    }

    void notify(T)(T var) {
        m_putMsg.notify;
    }

    static ref thisInfo() nothrow
    {
        static ThreadInfo ti;
        if(!ti) {
            debug writeln("New ThreadInfo");
            ti = new ThreadInfo();
        }
        return ti;
    }
}

class Channel(T) {
    DList!T queue;

    private:
    ThreadInfo ti;
    Mutex m_lock;

    void listen() {
        assert(!ti, "somebody is already listening to this channel");
        ti = ThreadInfo.thisInfo;
    }

    void close() {
        assert(ti == ThreadInfo.thisInfo, "You cannot close somebody elses channel");
        ti = ThreadInfo.init;
    }

    this() {
        m_lock = new Mutex;
    }

    void send(ref T val) {
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
