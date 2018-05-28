using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class CameraDepthTextureMode : MonoBehaviour
{
    public DepthTextureMode mode;
    private DepthTextureMode _cachedMode;

    // Use this for initialization
    void Start ()
    {
        _cachedMode = mode;
    }
	
	// Update is called once per frame
	void Update () {
	    if (_cachedMode != mode)
	    {
	        _cachedMode = mode;
	        Camera.main.depthTextureMode = _cachedMode;
	    }
	}
}
