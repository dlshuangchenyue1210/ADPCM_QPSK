function rx_sig = sim_channel(tx_sig, snr_db)
    rx_sig = awgn(tx_sig, snr_db, 'measured');
end