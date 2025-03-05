import core.thread;
import core.sync.condition;
import core.sync.mutex;

import std.stdio;
import std.container.dlist;

class Channel(T) {
    DList!T queue;

    private Mutex m_lock;
    private Condition m_putMsg;

    this() {
        m_lock = new Mutex;
        m_putMsg = new Condition(m_lock);
    }

    void send(ref T val) {
        synchronized(m_lock) {
            queue.insert(val);
            m_putMsg.notify();
        }
    }

    ref T recv() {
        synchronized(m_lock) {
            scope(success)
                queue.removeFront();

            if(queue.empty) {
                m_putMsg.wait();
            }
            return queue.front;
        }
    }
}

void main() {
    auto chn = new Channel!string;
    auto a = new shared(Msg)( 5, 3, "aaa");
    chn.send(a);
    writeln("Main ", a.asasas, &a);

    auto th = new Thread({
            auto b = chn.recv();
            b.asasas = "bbb";
            writeln("Work ", b.asasas, &b);
        /* foreach(_; 0..10) { */
        /*     auto b = chn.recv(); */
        /*     b.asasas = "bbb"; */
        /*     writeln("Work ", b.asasas, &b); */
        /* } */
    }).start;

    /* foreach(i; 0..10) { */
    /*     auto c = new shared Msg(i, 8, ""); */
    /*     Thread.sleep(10.msecs); */
    /*     chn.send(c); */
    /*     c.asasas = "ccc"; */
    /*     writeln("Main ", c.asasas, &c); */
    /* } */

    th.join();
}
