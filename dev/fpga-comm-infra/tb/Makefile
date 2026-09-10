.PHONY: all s2 s1 clean

all: s2 s1

s2:
	$(MAKE) -C udp_mcast_tx

s1:
	$(MAKE) -C tcp_pay_strip

clean:
	$(MAKE) -C udp_mcast_tx clean
	$(MAKE) -C tcp_pay_strip clean
