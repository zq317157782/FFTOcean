using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class Ocean : MonoBehaviour {
    //存放h0频谱信息的纹理[x:h0的实部 y:h0的虚部 z:w:]
    private RenderTexture _height0SpectrumTexture;
    private RenderTexture _heightSpectrumTexture;
    private RenderTexture _choppySpectrumTexture;
    private RenderTexture _butterflyTexture;
    private RenderTexture _ffTexture;
    private RenderTexture _ffTexture2;
    private RenderTexture _ffTexture3;
    private RenderTexture _ffTexture4;
    private RenderTexture[] _ffTextures;
    private RenderTexture _displacementMap;
    private RenderTexture _normalMap;
    private RenderTexture _flodMap;

    public int SizeOrder=9;
    private int _size;
    //[HideInInspector]
    public ComputeShader OceanShader;

    public Shader OceanRenderShader;
    private Material _material;
    public Material Mat;

    private int _height0SpectrumKernel;
    private int _heightSpectrumKernel;
    private int _horizontalButterfly;
    private int _verticalButterfly;
    private int _displacementKernel;
    private int _normalMapKernel;
    private int _foldMapKernel;

    public float Amplitude= 2*.00000000775f;
    public int Patch = 100;
    public float WindDirection = 0;
    public float WindSpeed = 10;
    public float Gravity=9.81f;
    public float HeightScale = 1;
    public float ChoppinessScale = 1;

    private ComputeBuffer _uniformSamples;
    

    private RenderTexture CreateTexture(int w,int h, RenderTextureFormat format, FilterMode filterMode = FilterMode.Bilinear)
    {
        RenderTexture tex= new RenderTexture(w, h, 0, format);
        tex.enableRandomWrite = true;
        tex.filterMode = filterMode;
        tex.Create();
        return tex;
    }


    private  int[] CountingSortByBit(int[] input,int bit)
    {
        // [0]=>0 [1]=>1
        int[] bitCount=new int[2];

        //用来存放排好序的
        int[] output=new int[input.Length];

        for (int i = 0; i < input.Length; ++i)
        {
            bitCount[(input[i] >> bit) & 0x1]++;
        }

        bitCount[1] = bitCount[1] + bitCount[0];

        for (int i = input.Length-1; i >=0 ; --i)
        {
            output[bitCount[(input[i] >> bit)&0x1]-1] = input[i];
            bitCount[(input[i] >> bit) & 0x1]--;
        }
        return output;
    }

    private int[] RadixSortByBits(int[] input, int maxBit)
    {
        int[] temp=input;
        int[] output;
        for (int i = maxBit-1; i>=0; --i)
        {
            output = CountingSortByBit(temp, i);
            temp = output;
        }
        output = temp;
        return output;
    }

    // Use this for initialization
    void Start ()
    {
        _material = Mat;
        if (_material == null)
        {
            _material = new Material(OceanRenderShader);
        }
        
        this.gameObject.GetComponent<MeshRenderer>().material = _material;

        _size = (int)Mathf.Pow(2, SizeOrder);
        _height0SpectrumTexture = CreateTexture(_size, _size, RenderTextureFormat.ARGBFloat);
        _heightSpectrumTexture = CreateTexture(_size, _size, RenderTextureFormat.ARGBFloat);
        _choppySpectrumTexture = CreateTexture(_size, _size, RenderTextureFormat.ARGBFloat);;
        _butterflyTexture = CreateTexture(SizeOrder, _size, RenderTextureFormat.ARGBInt,FilterMode.Point);
        _ffTexture = _heightSpectrumTexture;
        _ffTexture2 = CreateTexture(_size, _size, RenderTextureFormat.ARGBFloat);
        _ffTexture3 = _choppySpectrumTexture;
        _ffTexture4 = CreateTexture(_size, _size, RenderTextureFormat.ARGBFloat);
        _ffTextures =new RenderTexture[4];
        _ffTextures[0] = _ffTexture;
        _ffTextures[1] = _ffTexture2;
        _ffTextures[2] = _ffTexture3;
        _ffTextures[3] = _ffTexture4;
        _displacementMap = CreateTexture(_size, _size, RenderTextureFormat.ARGBFloat);
        _normalMap = CreateTexture(_size, _size, RenderTextureFormat.ARGB2101010);
        _normalMap.autoGenerateMips = true;

        _flodMap= CreateTexture(_size, _size, RenderTextureFormat.ARGBFloat);


        //注意这里的16是byte 4是float
        _uniformSamples = new ComputeBuffer(_size * _size,16);
        float[] uniformSamplesArray = new float[_size * _size * 4];
        for (int i = 0; i < _size * _size * 4; ++i)
        {
            uniformSamplesArray[i] = Random.Range(0.00001f, 1.0f);
        }
        _uniformSamples.SetData(uniformSamplesArray);

        //设置常量
        OceanShader.SetFloat("A", Amplitude);
        OceanShader.SetFloat("wd", WindDirection);
        OceanShader.SetFloat("wSpeed", WindSpeed);
        OceanShader.SetInt("patch", Patch);
        OceanShader.SetFloat("gravity", Gravity);
        OceanShader.SetInt("size", _size);
        OceanShader.SetFloat("heightScale", HeightScale);
        OceanShader.SetFloat("choppinessScale", ChoppinessScale);
        //执行生成Height0Spectrum纹理
        _height0SpectrumKernel = OceanShader.FindKernel("GenerateHeight0SpectrumTexture");
        OceanShader.SetBuffer(_height0SpectrumKernel, "UniformSamples", _uniformSamples);
        OceanShader.SetTexture(_height0SpectrumKernel, "Height0SpectrumTexture", _height0SpectrumTexture);
        OceanShader.Dispatch(_height0SpectrumKernel, _size / 8, _size/8,1);



        int[] revIndices = new int[512];
        for (int i = 0; i < 512; ++i)
        {
            revIndices[i] = i;
        }

        revIndices = RadixSortByBits(revIndices, 9);
        ComputeBuffer reserveBit = new ComputeBuffer(512, 4);
        reserveBit.SetData(revIndices);
        int _butterflyKeneral = OceanShader.FindKernel("GenerateButterfly");
        OceanShader.SetBuffer(_butterflyKeneral, "ReserveBit", reserveBit);
        OceanShader.SetTexture(_butterflyKeneral, "ButterflyTex", _butterflyTexture);
        OceanShader.Dispatch(_butterflyKeneral, SizeOrder, _size/8, 1);



        _heightSpectrumKernel = OceanShader.FindKernel("GenerateHeightSpectrumTexture");

        _horizontalButterfly = OceanShader.FindKernel("HorizontalButterfly");
        _verticalButterfly = OceanShader.FindKernel("VerticalButterfly");
        _displacementKernel= OceanShader.FindKernel("GenerateDisplacement");
        _normalMapKernel = OceanShader.FindKernel("GenerateNormalMap");
        _foldMapKernel = OceanShader.FindKernel("GenerateFoldMap");
    }
	
	// Update is called once per frame
	void Update () {
#if UNITY_EDITOR
	    //设置常量
	    OceanShader.SetFloat("A", Amplitude);
	    OceanShader.SetFloat("wd", WindDirection);
	    OceanShader.SetFloat("wSpeed", WindSpeed);
	    OceanShader.SetInt("patch", Patch);
	    OceanShader.SetFloat("gravity", Gravity);
	    OceanShader.SetInt("size", _size);
	    OceanShader.SetFloat("heightScale", HeightScale);
	    OceanShader.SetFloat("choppinessScale", ChoppinessScale); 
        OceanShader.Dispatch(_height0SpectrumKernel, _size / 8, _size / 8, 1);
	  
#endif

        OceanShader.SetFloat("t",Time.fixedTime);
        OceanShader.SetTexture(_heightSpectrumKernel, "Height0SpectrumTexture", _height0SpectrumTexture);
	    OceanShader.SetTexture(_heightSpectrumKernel, "ChoppySpectrumTexture", _choppySpectrumTexture);
        OceanShader.SetTexture(_heightSpectrumKernel, "HeightSpectrumTexture", _heightSpectrumTexture);
	    OceanShader.Dispatch(_heightSpectrumKernel, _size / 8, _size / 8, 1);

	    int inputIndex = 0;
	    int outputIndex = 1;

        for (int stage = 0; stage < SizeOrder; ++stage)
        {

            OceanShader.SetTexture(_horizontalButterfly, "ButterflyTex", _butterflyTexture);
            OceanShader.SetTexture(_horizontalButterfly, "FFTInput", _ffTextures[inputIndex]);
            OceanShader.SetTexture(_horizontalButterfly, "FFTOutput", _ffTextures[outputIndex]);
            OceanShader.SetTexture(_horizontalButterfly, "FFTInput2", _ffTextures[inputIndex + 2]);
            OceanShader.SetTexture(_horizontalButterfly, "FFTOutput2", _ffTextures[outputIndex + 2]);
            OceanShader.SetInt("stage", stage);
            OceanShader.Dispatch(_horizontalButterfly, _size / 8, _size / 8, 1);
            inputIndex = (inputIndex + 1) % 2;
            outputIndex = (outputIndex + 1) % 2;
        }

        for (int stage = 0; stage < SizeOrder; ++stage)
        {

            OceanShader.SetTexture(_verticalButterfly, "ButterflyTex", _butterflyTexture);
            OceanShader.SetTexture(_verticalButterfly, "FFTInput", _ffTextures[inputIndex]);
            OceanShader.SetTexture(_verticalButterfly, "FFTOutput", _ffTextures[outputIndex]);
            OceanShader.SetTexture(_verticalButterfly, "FFTInput2", _ffTextures[inputIndex + 2]);
            OceanShader.SetTexture(_verticalButterfly, "FFTOutput2", _ffTextures[outputIndex + 2]);
            OceanShader.SetInt("stage", stage);
            OceanShader.Dispatch(_verticalButterfly, _size / 8, _size / 8, 1);
            inputIndex = (inputIndex + 1) % 2;
            outputIndex = (outputIndex + 1) % 2;
        }




        OceanShader.SetTexture(_displacementKernel, "DisplacementInput", _ffTextures[inputIndex]);
        OceanShader.SetTexture(_displacementKernel, "DisplacementInput2", _ffTextures[inputIndex + 2]);
        OceanShader.SetTexture(_displacementKernel, "DisplacementOutput", _displacementMap);
        OceanShader.Dispatch(_displacementKernel, _size / 8, _size / 8, 1);

	    OceanShader.SetTexture(_normalMapKernel, "DisplacementOutput", _displacementMap);
	    OceanShader.SetTexture(_normalMapKernel, "NormalMap", _normalMap);
	    OceanShader.Dispatch(_normalMapKernel, _size / 8, _size / 8, 1);

	    OceanShader.SetTexture(_foldMapKernel, "DisplacementOutput", _displacementMap);
	    OceanShader.SetTexture(_foldMapKernel, "FoldMap", _flodMap);
	    OceanShader.Dispatch(_foldMapKernel, _size / 8, _size / 8, 1);


        _material.SetTexture("_DisplacementMap", _displacementMap);
	    _material.SetTexture("_NormalMap", _normalMap);
        _material.SetTexture("_FoldMap", _flodMap);
        _material.SetFloat("_WindDir",WindDirection);
    }
}
