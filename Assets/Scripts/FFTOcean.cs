using System.Collections;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

public class FFTOcean : MonoBehaviour
{

    public ComputeShader OceanComputeShader;
    public Material Mat;
   

    int[] CountingSortByBit(int[] input,int bit)
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

    int[] RadixSortByBits(int[] input, int maxBit)
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

    private RenderTexture heightTex0;

    private RenderTexture pingpong01;
    private RenderTexture pingpong02;

    private RenderTexture pingpong01CP;
    private RenderTexture pingpong02CP;

    private RenderTexture[] pingpong = new RenderTexture[2];
    private RenderTexture[] pingpongCP = new RenderTexture[2];

    private RenderTexture butterfly;

    private RenderTexture finalPassOutput;

    private RenderTexture normalMap;

    // Use this for initialization
    void Start ()
    {

        ComputeBuffer uniform01Data = new ComputeBuffer(512*512,16);
        float[] uniform01Array=new float[512*512*4];
        for (int i = 0; i < 512*512 * 4; ++i)
        {
            uniform01Array[i] = Random.Range(0.00001f, 1.0f);
        }
        uniform01Data.SetData(uniform01Array);

        ComputeBuffer uniform01Data2 = new ComputeBuffer(512 * 512, 16);
        float[] uniform01Array2 = new float[512 * 512 * 4];
        for (int i = 0; i < 512 * 512 * 4; ++i)
        {
            uniform01Array2[i] = Random.Range(0.00001f, 1.0f);
        }
        uniform01Data2.SetData(uniform01Array2);

        heightTex0=new RenderTexture(512,512,0,RenderTextureFormat.ARGBFloat);
        heightTex0.enableRandomWrite = true;
        heightTex0.filterMode = FilterMode.Bilinear;
        heightTex0.Create();
            
        pingpong01 = new RenderTexture(512, 512, 0, RenderTextureFormat.ARGBFloat);
        pingpong01.enableRandomWrite = true;
        pingpong01.filterMode = FilterMode.Bilinear;
        pingpong01.Create();

        pingpong02 = new RenderTexture(512, 512, 0, RenderTextureFormat.ARGBFloat);
        pingpong02.enableRandomWrite = true;
        pingpong02.filterMode = FilterMode.Bilinear;
        pingpong02.Create();

        pingpong[0] = pingpong01;
        pingpong[1] = pingpong02;



        pingpong01CP = new RenderTexture(512, 512, 0, RenderTextureFormat.ARGBFloat);
        pingpong01CP.enableRandomWrite = true;
        pingpong01CP.filterMode = FilterMode.Bilinear;
        pingpong01CP.Create();

        pingpong02CP = new RenderTexture(512, 512, 0, RenderTextureFormat.ARGBFloat);
        pingpong02CP.enableRandomWrite = true;
        pingpong02CP.filterMode = FilterMode.Bilinear;
        pingpong02CP.Create();

        pingpongCP[0] = pingpong01CP;
        pingpongCP[1] = pingpong02CP;


        butterfly = new RenderTexture(9, 512, 0, RenderTextureFormat.ARGBFloat);
        butterfly.enableRandomWrite = true;
        butterfly.filterMode = FilterMode.Bilinear;
        butterfly.Create();

        finalPassOutput = new RenderTexture(512, 512, 0, RenderTextureFormat.ARGBFloat);
        finalPassOutput.enableRandomWrite = true;
        finalPassOutput.filterMode = FilterMode.Bilinear;
        finalPassOutput.wrapMode = TextureWrapMode.Repeat;
        finalPassOutput.Create();
       

        normalMap = new RenderTexture(512, 512, 0, RenderTextureFormat.ARGBFloat);
        normalMap.enableRandomWrite = true;
        normalMap.filterMode = FilterMode.Bilinear;
        normalMap.wrapMode = TextureWrapMode.Repeat;
        normalMap.Create();
        

        int[] revIndices = new int[512];
        for (int i = 0; i < 512; ++i)
        {
            revIndices[i] = i;
        }

        int[] test= RadixSortByBits(revIndices,9);
        Debug.Log(string.Join(", ", value: test.Select(e=>e.ToString()).ToArray()));
        ComputeBuffer reserveBit = new ComputeBuffer(512,4);
        reserveBit.SetData(test);


        int k = OceanComputeShader.FindKernel("Height0");
        OceanComputeShader.SetTexture(k, "Height0Tex", heightTex0);
        OceanComputeShader.SetFloat("unit",100);
        OceanComputeShader.SetInt("N",512);
        OceanComputeShader.SetVector("windDirection",new Vector4(1,1,0,0));
        OceanComputeShader.SetFloat("windSpeed",10);
        OceanComputeShader.SetFloat("A", 2f);
        OceanComputeShader.SetFloat("gravity",9.81f);
        OceanComputeShader.SetBuffer(k, "uniform01Data", uniform01Data);
        OceanComputeShader.SetBuffer(k, "uniform01Data2", uniform01Data2);
        OceanComputeShader.Dispatch(k,512/8,512/8,1);

       

        int k3 = OceanComputeShader.FindKernel("Butterfly");
        OceanComputeShader.SetBuffer(k3, "reserveBit", reserveBit);
        OceanComputeShader.SetTexture(k3, "ButterflyTex", butterfly);
        OceanComputeShader.Dispatch(k3, 9, 512 / 8, 1);



      
       // Mat.SetTexture("_MainTex", butterfly);
        uniform01Data.Release();
        uniform01Data2.Release();
        reserveBit.Release();

    }
	
	// Update is called once per frame
	void Update () {

	    int k2 = OceanComputeShader.FindKernel("Height");
	    OceanComputeShader.SetTexture(k2, "Height0Tex", heightTex0);
	    OceanComputeShader.SetTexture(k2, "HeightTex", pingpong01);
	    OceanComputeShader.SetTexture(k2, "ChoppyTex", pingpong01CP);
        OceanComputeShader.SetFloat("t", Time.fixedTime);
	    OceanComputeShader.Dispatch(k2, 512 / 8, 512 / 8, 1);

        int inputIndex = 0;
        int outputIndex = 1;

        for (int stage = 0; stage < 9; ++stage)
        {
            int k4 = OceanComputeShader.FindKernel("HorizontalButterfly");
            OceanComputeShader.SetTexture(k4, "ButterflyTex", butterfly);
            OceanComputeShader.SetTexture(k4, "ButterflyInput", pingpong[inputIndex]);
            OceanComputeShader.SetTexture(k4, "ButterflyOutput", pingpong[outputIndex]);
            OceanComputeShader.SetTexture(k4, "ButterflyInputCP", pingpongCP[inputIndex]);
            OceanComputeShader.SetTexture(k4, "ButterflyOutputCP", pingpongCP[outputIndex]);
            OceanComputeShader.SetInt("stage", stage);
            OceanComputeShader.Dispatch(k4, 512 / 8, 512 / 8, 1);

            inputIndex = (inputIndex + 1) % 2;
            outputIndex = (outputIndex + 1) % 2;
        }


        //   for (int stage = 0; stage < 9; ++stage)
        //   {
        //       int k4 = OceanComputeShader.FindKernel("VerticalButterfly");
        //       OceanComputeShader.SetTexture(k4, "ButterflyTex", butterfly);
        //       OceanComputeShader.SetTexture(k4, "ButterflyInput", pingpong[inputIndex]);
        //       OceanComputeShader.SetTexture(k4, "ButterflyOutput", pingpong[outputIndex]);
        //       OceanComputeShader.SetTexture(k4, "ButterflyInputCP", pingpongCP[inputIndex]);
        //       OceanComputeShader.SetTexture(k4, "ButterflyOutputCP", pingpongCP[outputIndex]);
        //       OceanComputeShader.SetInt("stage", stage);
        //       OceanComputeShader.Dispatch(k4, 512 / 8, 512 / 8, 1);

        //       inputIndex = (inputIndex + 1) % 2;
        //       outputIndex = (outputIndex + 1) % 2;
        //   }

        //   int k5 = OceanComputeShader.FindKernel("FinalPass");
        //   OceanComputeShader.SetTexture(k5, "FinalPassInput", pingpong[inputIndex]);
        //   OceanComputeShader.SetTexture(k5, "FinalPassChoppyInput", pingpongCP[inputIndex]);
        //   OceanComputeShader.SetTexture(k5, "FinalPassOutput", finalPassOutput);
        //   OceanComputeShader.Dispatch(k5, 512 / 8, 512 / 8, 1);


        //int k6 = OceanComputeShader.FindKernel("NormalMap");
        //OceanComputeShader.SetTexture(k6, "DisplacementMap", finalPassOutput);
        //OceanComputeShader.SetTexture(k6, "NormalMapTex", normalMap);
        //OceanComputeShader.Dispatch(k6, 512 / 8, 512 / 8, 1);

        Mat.SetTexture("_MainTex", pingpong[inputIndex]);
	    Mat.SetTexture("_NormalMap", normalMap);
    }
}
