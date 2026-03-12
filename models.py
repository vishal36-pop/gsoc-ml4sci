import torch
import torch.nn as nn

class ResidualBlock(nn.Module):
    def __init__(self,inplanes ,planes,shortcut = None,downsample = False,*args, **kwargs):
        super().__init__()
        if downsample == True:
            self.stride = 2
        else:
            self.stride = 1 
        self.layer1 = nn.Conv2d(inplanes,planes,3,self.stride,padding=1)
        self.activation = nn.ReLU()
        self.layer2 = nn.Conv2d(in_channels = planes,out_channels= planes,kernel_size=3,stride =1,padding=1)
        self.shortcut = shortcut
        self.downsample = downsample
        self.norm = nn.BatchNorm2d(planes)

    def forward(self,x) :
        shortcut = 0
        if self.shortcut:
            shortcut = self.shortcut(x)
        x = self.layer1(x)
        x = self.norm(x)
        x = self.activation(x)
        x = self.layer2(x)
        x = self.norm(x)
        return self.activation(x+shortcut)

class Bottleneck(nn.Module):
    def __init__(self,inplanes,planes,downsample = False,shortcut = None):
        super().__init__()
        self.stride = None
        if downsample == True:
            self.stride = 2
        else :
            self.stride = 1
        self.layer1 = nn.Conv2d(inplanes,planes,1,self.stride,padding=0)
        self.layer2 = nn.Conv2d(planes,planes,3,1,padding=1)
        self.layer3 = nn.Conv2d(planes,planes,1,padding=0)
        self.shortcut  = shortcut
        self.activation  = nn.ReLU()
        self.norm = nn.BatchNorm2d(planes)
    def forward(self,x):
        shortcut = 0 
        if self.shortcut:
            shortcut = self.shortcut(x)
        x = self.layer1(x)
        x = self.norm(x)
        x = self.activation(x)
        x = self.layer2(x)
        x = self.norm(x)
        x = self.activation(x)
        x = self.layer3(x)
        x = x+shortcut
        return self.activation(x)

class Upscale(nn.Module):
    def __init__(self,inplanes,planes = None,expansion =2, *args, **kwargs):
        super().__init__()
        if planes:
            self.upscale = nn.ConvTranspose2d(inplanes,planes,kernel_size=2,stride=2)
        else:
            self.upscale = nn.ConvTranspose2d(inplanes,inplanes*expansion,kernel_size=2,stride=2)

        self.norm = nn.BatchNorm2d(inplanes*2)
        self.activation = nn.ReLU()
        self.expansion = expansion
    def forward(self,x):
        x = self.upscale(x)
        x = self.norm(x)
        return self.activation(x)

class convnet(nn.Module):
    def __init__(self, layers: list, inplanes, expansion=2):
        super().__init__()
        self.no_blocks_in_layers = layers
        self.expansion = expansion
        
        self.inplanes = 64 #used for book keeping such that it keep track of the planes of the prev layer
        # Output calculation: Floor((125 + 2*2 - 3)/2 + 1) = Floor(126/2 + 1) = 64
        self.layer1 = nn.Sequential(
                nn.Conv2d(in_channels=inplanes, out_channels=64, kernel_size=3, stride=2, padding=2),
                nn.BatchNorm2d(64),
            ) # the first ever layer
        self.layers = nn.ModuleList()
        self.globalavgpool = nn.AdaptiveAvgPool2d((1,1))
        self.build_layers()
        
    @property
    def no_of_layers(self):
        return len(self.no_blocks_in_layers)
    
    def make_layer_Res(self,no_of_blocks,planes,downsample):
        blocks = []
        if downsample == True:
            blocks.append(ResidualBlock(self.inplanes,planes,downsample=True,shortcut=nn.Conv2d(self.inplanes,planes,1,2)))
        for i in range(no_of_blocks-1):
            blocks.append(ResidualBlock(planes,planes,shortcut=nn.Identity()))
        self.inplanes = planes
        return nn.Sequential(*blocks)
    
    def make_layer_Botl(self,no_of_blocks,planes,downsample):
        blocks = []
        if downsample == True:
            blocks.append(Bottleneck(self.inplanes,planes,downsample=True,shortcut=nn.Conv2d(self.inplanes,planes,1,2)))
        for i in range(no_of_blocks-1):
            blocks.append(Bottleneck(planes,planes,shortcut=nn.Identity()))
        self.inplanes = planes
        return nn.Sequential(*blocks)
    
    def build_layers(self):
        blocks_count = 0
        total_blocks = sum(self.no_blocks_in_layers)
        
        # We apply bottlenecks when layers > 50 (approx 24 blocks), roughly after halfway
        # Alternatively, we just use a hardcoded threshold
        bottleneck_treshold = total_blocks // 2 if total_blocks >= 24 else float('inf')
        
        for i in range(self.no_of_layers):
            if i == 0:
                self.layers.append(self.make_layer_Res(self.no_blocks_in_layers[i],self.inplanes,False))
                blocks_count += self.no_blocks_in_layers[i]
                continue 
            if blocks_count < bottleneck_treshold :
                self.layers.append(self.make_layer_Res(self.no_blocks_in_layers[i],self.inplanes*self.expansion,True))
            else:
                self.layers.append(self.make_layer_Botl(self.no_blocks_in_layers[i],self.inplanes*self.expansion,True))
            blocks_count += self.no_blocks_in_layers[i]

    def forward(self,x) :
        x = self.layer1(x)
        for i in self.layers:
            x = i(x)
        x = self.globalavgpool(x)
        return x
