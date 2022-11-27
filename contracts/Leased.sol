// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

contract Leased{

    uint immutable mortgage; //مقدار رهن
    uint immutable rent; //مقدار اجاره
    uint public startDate; //زمان شروع قرارداد اجاره
    address payable public lessor; //آدرس موجر
    address payable  public tenant; //آدرس مستاجر
    uint8 public number; //تعداد احاره های پراخت شده توسط مستاجر
    uint immutable delay;  // مبلغ جریمه مستاجر بابت هر روز دیرکرد پرداخت اجاره
    uint public lateAmount; //مبلغ جریمه کل که بابت دیرکرد اجاره از مقدار رهن مستاجر کسر خواهد شد
    uint longDelay; //تاریخ موعد پرداخت اجاره در هر ماه
    bool lock; //برای جلوگیری از حمله ورود مجدد

    enum Status{   
        notStarted,
        accepted,
        started,
        finished,
        endOfContract
    }
    Status public status;

    event sentMortgage(address _tenant, uint value);
    event sentRent(uint _number);

    constructor(uint _mortgage, uint _rent){  //تعیین مقدار رهن و اجاره از سوی موجر
        lessor = payable(msg.sender);
        mortgage = _mortgage;
        rent = _rent;
        delay = mortgage / 100;
    }

    modifier onlyNotStarted(){
        require(status == Status.notStarted, "You are not allowed!");
        _;
    }

    function accept() public onlyNotStarted{   //پذیرفتن شرایط رهن و احاره ی تعیین شده توسط موجر ار سوی مستاجر
        tenant = payable(msg.sender);
        status = Status.accepted;
    }

    modifier onlyAccepted(){
        require(status == Status.accepted, "You are not allowed");
        _;
    }

    function sendMortgage() public payable onlyAccepted{  //ارسال مقدار رهن به آٰدرس موجر و شروع تاریخ اجاره
        require(msg.value == mortgage, "The amount you sent is not equal to the mortgage");
        startDate = block.timestamp;
        status = Status.started;
        emit sentMortgage(tenant, msg.value);
    }

    modifier onlyStarted(){
        require(status == Status.started, "You are not allowed");
        _;
    }

    function rentPayment() public payable onlyStarted{  //ارسال مبلغ اجاره به حساب موجر
        require(msg.value == rent, "The amount you sent is not equal to the rent!");

        longDelay = block.timestamp - (startDate + ((number+1) * 30 days));
        if (longDelay > 100)  //چک می کند که آیا مهلت زمانی دیرکرد اجاره به پایان رسیده است یا نه
            expire();

        else if (longDelay > 5 && longDelay <= 100) //محاسبه میزان جریمه ی این ماه مستاجر به دلیل دیرکرد در پرداخت اجاره
            lateAmount += (longDelay * delay);
        
        require(!lock);
        lock = true;
        (bool sent, ) = lessor.call{value: msg.value}("");
        require(sent, "Ethers could not be sent");
        lock = false;

        emit sentRent(number);
        number ++;

        if (number == 12){  //چک می کند که آیا تعداد ماه های اجاره به پایان رسیده است یا خیر
            status = Status.finished;
            finally();
        }
           

    }

    modifier onlyFinished(){
        require(number == 12, "The number of months of rent has not yet ended");
        _;
    }

    function finally() private onlyFinished{  //این فانکشن فقط در صورت اتمام ماه های اجاره اجرا می شود و در طی آن مبلغ جریمه ی مستاجر از میزان رهن کسر می شود و مابقی رهن به حساب مستاجر ارسال می شود
        require(!lock);
        lock = true;
        (bool sentTenant, ) = tenant.call{value: mortgage - lateAmount}("");
        require(sentTenant, "Ethers could not be sent to the tenant");
        (bool sentLessor, ) = lessor.call{value: lateAmount}("");
        require(sentLessor, "Ethers could not be sent to the lessor");
        lock = false;
        status = Status.endOfContract;

    }

    modifier onlyExpire(){
        longDelay = block.timestamp - (startDate + ((number+1) * 30 days));
        require(longDelay > 100, "The tenant still has a deadline");
        _;
    }    

    function expire() public onlyStarted onlyExpire{  //اگر مهلت صد روزه ی مستاجر برای پرداخت اجاره به پایان برسد کل مبلغ رهن به حساب موجر ارسال شده و قرارداد فسخ می شود
        require(!lock);
        lock = true;
        (bool sentLessor, ) = lessor.call{value: mortgage}("");
        require(sentLessor, "Ethers could not be sent to the lessor");
        lock = false;
        status = Status.endOfContract;
    }

}