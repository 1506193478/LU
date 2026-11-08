package com.lu.media;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
  @Override
  public void onCreate(android.os.Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    registerPlugin(com.lu.media.TcpSocketPlugin.class);
  }
}
